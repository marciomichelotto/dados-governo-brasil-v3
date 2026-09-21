"""
carrega_bronze.py — carrega despesasPorOrgao.csv (baixado manualmente do
Portal da Transparência) pro bronze, sem stage S3, e dispara
SP_BRONZE_TO_SILVER().

O arquivo do Portal vem com uma particularidade: cada LINHA inteira é
envolvida por um par de aspas (`"campo1\tcampo2\t...\tcampoN"`), não cada
campo individualmente — o parser CSV padrão do Snowflake (COPY INTO)
interpretaria a linha toda como um único campo. Aqui só removemos as aspas
de borda e fazemos split por tab manualmente, mais simples e correto que
lutar contra o FILE_FORMAT do Snowflake pra esse formato específico.

Uso:
    python carrega_bronze.py --entrada ./data/raw/despesasPorOrgao.csv
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path

import snowflake.connector

ROOT = Path(__file__).resolve().parent.parent
COLUNAS = [
    "mes_ano", "orgao_superior", "orgao_vinculado",
    "valor_empenhado", "valor_liquidado", "valor_pago", "valor_restos_pagar",
]


def le_linhas(path: Path) -> list[tuple[str, ...]]:
    linhas = []
    with open(path, encoding="latin-1") as f:
        header = True
        for linha in f:
            linha = linha.strip().strip('"')
            if not linha:
                continue
            if header:
                header = False
                continue
            campos = linha.split("\t")
            if len(campos) != len(COLUNAS):
                continue
            linhas.append(tuple(campos))
    return linhas


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--entrada", type=Path, default=ROOT / "data/raw/despesasPorOrgao.csv")
    args = ap.parse_args()

    linhas = le_linhas(args.entrada)
    print(f"lidas {len(linhas)} linhas de {args.entrada.name}")

    con = snowflake.connector.connect(
        account="RZFQSVC-JX11949",
        user="MARCIOMICHELOTTO",
        password=os.environ["SNOWFLAKE_PASSWORD"],
        role="ACCOUNTADMIN",
        warehouse="COMPUTE_WH",
        database="GOV_V3",
        schema="DADOS_GOV",
    )
    cur = con.cursor()

    cur.execute("TRUNCATE TABLE TB_BRONZE_DESPESAS_V2")
    placeholders = ", ".join(["%s"] * len(COLUNAS))
    # sem PARSE_JSON nem função nenhuma nos valores — executemany consegue
    # fazer o rewrite pra multi-row insert aqui (ao contrário do bronze do
    # northwind, que tinha PARSE_JSON e obrigava linha a linha).
    cur.executemany(
        f"INSERT INTO TB_BRONZE_DESPESAS_V2 ({', '.join(COLUNAS)}) VALUES ({placeholders})",
        linhas,
    )
    print(f"  TB_BRONZE_DESPESAS_V2  {len(linhas):>5} linhas")

    cur.execute("CALL SP_BRONZE_TO_SILVER()")
    print(" ", cur.fetchone()[0])

    cur.execute("SELECT COUNT(*) FROM TB_SILVER_DESPESAS")
    print("TB_SILVER_DESPESAS:", cur.fetchone()[0], "linhas")

    con.close()


if __name__ == "__main__":
    main()
