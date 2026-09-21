"""
deploy_snowflake.py — aplica o DDL de infraestrutura e as procedures no
Snowflake configurado em dbt/profiles.yml (via SNOWFLAKE_PASSWORD no
ambiente). Idempotente: setup usa CREATE ... IF NOT EXISTS, tabelas e
procedures usam CREATE OR REPLACE.

Não deploya snowflake/setup/02_stage.sql (stage S3) nem
snowflake/procedures/sp_bronze_load.sql (COPY INTO do stage) — sem bucket S3
configurado, scripts/carrega_bronze.py carrega o bronze direto do CSV local.

Uso:
    python deploy_snowflake.py
"""

from __future__ import annotations

import os
from pathlib import Path

import snowflake.connector

ROOT = Path(__file__).resolve().parent.parent

ARQUIVOS = [
    ROOT / "snowflake/setup/01_database.sql",
    ROOT / "snowflake/setup/03_tables.sql",
    ROOT / "snowflake/procedures/sp_silver_clean.sql",
]


def split_statements(sql_text: str) -> list[str]:
    partes: list[str] = []
    atual: list[str] = []
    dentro_dollar = False
    dentro_comentario = False
    i = 0
    while i < len(sql_text):
        if dentro_comentario:
            atual.append(sql_text[i])
            if sql_text[i] == "\n":
                dentro_comentario = False
            i += 1
            continue
        if not dentro_dollar and sql_text[i : i + 2] == "--":
            dentro_comentario = True
            atual.append("--")
            i += 2
            continue
        if sql_text[i : i + 2] == "$$":
            dentro_dollar = not dentro_dollar
            atual.append("$$")
            i += 2
            continue
        if sql_text[i] == ";" and not dentro_dollar:
            partes.append("".join(atual))
            atual = []
            i += 1
            continue
        atual.append(sql_text[i])
        i += 1
    partes.append("".join(atual))

    def tem_conteudo(stmt: str) -> bool:
        sem_comentarios = "\n".join(
            l for l in stmt.splitlines() if not l.strip().startswith("--")
        )
        return bool(sem_comentarios.strip())

    return [p.strip() for p in partes if tem_conteudo(p)]


def carrega_env(path: Path) -> None:
    if not path.exists():
        return
    for linha in path.read_text(encoding="utf-8").splitlines():
        linha = linha.strip()
        if not linha or linha.startswith("#") or "=" not in linha:
            continue
        chave, valor = linha.split("=", 1)
        if valor and chave not in os.environ:
            os.environ[chave] = valor


def main() -> None:
    con = snowflake.connector.connect(
        account="RZFQSVC-JX11949",
        user="MARCIOMICHELOTTO",
        password=os.environ["SNOWFLAKE_PASSWORD"],
        role="ACCOUNTADMIN",
        warehouse="COMPUTE_WH",
    )
    cur = con.cursor()
    for path in ARQUIVOS:
        for stmt in split_statements(path.read_text(encoding="utf-8")):
            try:
                cur.execute(stmt)
            except Exception:
                print(f"FALHOU em {path}:\n---\n{stmt}\n---")
                raise
        print(f"  ok  {path.relative_to(ROOT)}")
    con.close()
    print(f"\n{len(ARQUIVOS)} arquivos aplicados.")


if __name__ == "__main__":
    main()
