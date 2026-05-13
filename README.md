# Dados Governo Brasil v3

Pipeline de dados em **Snowflake + dbt** para ingestão, tratamento e análise de despesas públicas federais em arquitetura **Medallion (Bronze → Silver → Gold)** — com carga incremental via `MERGE`, testes automatizados de qualidade e CI/CD com validação obrigatória antes do deploy.

---

## 🎯 O problema que este projeto resolve

O [Portal da Transparência](https://portaldatransparencia.gov.br) disponibiliza dados brutos de despesas por órgão em CSV — mas o formato muda sem aviso, os números usam padrão brasileiro (vírgula decimal, ponto de milhar) e datas chegam como texto (`mar/25`). Sem um pipeline estruturado, qualquer análise começa com horas de limpeza manual.

Este projeto automatiza esse processo de ponta a ponta, permitindo responder perguntas como:

- Quais ministérios têm **menor taxa de execução orçamentária**?
- Quais órgãos acumulam **alto volume de restos a pagar** — indicador crítico de risco fiscal?
- Como a execução evoluiu mês a mês ao longo do ano?

---

## 🏗️ Arquitetura

```mermaid
flowchart LR
    A[("Portal da\nTransparência\n(CSV)")] -->|COPY INTO\nON_ERROR=CONTINUE| B

    subgraph Snowflake
        B[("🥉 BRONZE\nDados brutos\nVARCHAR/VARIANT")]
        -->|SP_BRONZE_TO_SILVER\nMERGE + TRY_CAST| C

        C[("🥈 SILVER\nDados limpos\ntipados e padronizados")]
        -->|SP_SILVER_TO_GOLD\nMERGE + agregações| D

        D[("🥇 GOLD\nIndicadores\nagreg. por mês/órgão")]
    end

    D -->|dbt run| E

    subgraph dbt ["dbt (views analíticas)"]
        E["vw_ranking_ministerios\nvw_restos_a_pagar\nvw_execucao_orcamentaria\nvw_alertas_criticos"]
    end

    E --> F[("📊 Power BI\n/ BI Tools")]

    subgraph CI/CD [".github/workflows"]
        G["✅ validate\n(sqlfluff + dbt compile\n+ dbt test)"]
        -->|needs: validate\nonly: main| H["🚀 deploy\n(SnowSQL + dbt run)"]
    end
```

---

## 🧱 Camadas

### 🥉 Bronze
Ingestão bruta sem regras de negócio — preserva os dados originais.

| Tabela | Formato | Descrição |
|---|---|---|
| `TB_BRONZE_DESPESAS` | `VARIANT` | Ingestão via semi-estruturado |
| `TB_BRONZE_DESPESAS_V2` | `VARCHAR` | Staging estruturado para CSV/TSV |

### 🥈 Silver
Qualidade e padronização. Carga incremental via **MERGE** (idempotente).

| Tabela | Chave de negócio |
|---|---|
| `TB_SILVER_DESPESAS` | `orgao_subordinado_cod` + `mes_ano_dt` |

Transformações aplicadas:
- `mes_ano` (ex: `mar/25`) → `DATE` (primeiro dia do mês)
- Números BR (`1.234,56`) → `NUMBER(20,2)` via `TRY_CAST`
- Limpeza de aspas e espaços (`TRIM`)
- Campos de auditoria: `dt_carga_silver`, `arquivo_origem`

### 🥇 Gold
Camada analítica para consumo por BI e relatórios. Carga incremental via **MERGE**.

| Objeto | Tipo | Descrição |
|---|---|---|
| `TB_GOLD_DESPESAS_AGREG` | Tabela | Agregações por mês e órgão superior |
| `vw_ranking_ministerios` | dbt view | Ranking por volume de pagamentos |
| `vw_restos_a_pagar` | dbt view | Órgãos com maior acúmulo de RAP |
| `vw_execucao_orcamentaria` | dbt view | Eficiência: ALTA / MEDIA / BAIXA |
| `vw_alertas_criticos` | dbt view | Cruzamento: baixa execução + alto RAP |

---

## 📁 Estrutura do repositório

```
dados-governo-brasil-v3/
│
├── .github/
│   └── workflows/
│       └── deploy.yml          # CI: validate → deploy (só main)
│
├── snowflake/
│   ├── setup/
│   │   ├── 01_database.sql     # Database, schemas, warehouse
│   │   ├── 02_stage.sql        # Stage externo (AWS S3) + file format
│   │   └── 03_tables.sql       # DDL Bronze, Silver e Gold
│   ├── procedures/
│   │   ├── sp_bronze_load.sql  # Carga Bronze via COPY INTO
│   │   └── sp_silver_clean.sql # Bronze→Silver e Silver→Gold (MERGE)
│   └── tasks/
│       └── orchestration.sql   # Cadeia de Tasks automáticas
│
├── dbt/
│   ├── dbt_project.yml
│   ├── packages.yml            # dbt-utils
│   ├── schema.yml              # Documentação + testes de qualidade
│   └── models/
│       └── gold/
│           ├── vw_ranking_ministerios.sql
│           ├── vw_restos_a_pagar.sql
│           ├── vw_execucao_orcamentaria.sql
│           └── vw_alertas_criticos.sql
│
└── README.md
```

---

## ⚙️ Pré-requisitos

- Conta Snowflake com permissões para criar objetos (DB, schema, stage, tabelas, procedures, tasks)
- Warehouse ativo (padrão: `COMPUTE_WH`)
- Stage externo configurado (`@AWS_STAGE`) com o arquivo `despesasPorOrgao(in).csv`
- Python 3.11+ com `dbt-snowflake` instalado
- GitHub Secrets configurados (ver seção CI/CD)

---

## 🚀 Execução (ordem sugerida)

### 1. Setup inicial no Snowflake

```sql
-- Execute nesta ordem:
-- 1. snowflake/setup/01_database.sql
-- 2. snowflake/setup/02_stage.sql
-- 3. snowflake/setup/03_tables.sql
```

### 2. Carga e transformações

```sql
-- Bronze
CALL SP_BRONZE_LOAD();

-- Silver (MERGE — pode rodar N vezes sem duplicar)
CALL SP_BRONZE_TO_SILVER();

-- Gold (MERGE — agrega e calcula KPIs)
CALL SP_SILVER_TO_GOLD();
```

### 3. Orquestração automática (opcional)

```sql
-- Cria a cadeia de Tasks com agendamento via CRON:
-- snowflake/tasks/orchestration.sql
--
-- Resultado:
--   TASK_CARREGA_BRONZE → AFTER → TASK_BRONZE_TO_SILVER
--                                       → AFTER → TASK_SILVER_TO_GOLD
```

### 4. Modelos analíticos (dbt)

```bash
# Instalar dependências
dbt deps

# Rodar modelos Gold
dbt run --select gold

# Executar testes de qualidade
dbt test --select gold

# Documentação navegável (lineage graph)
dbt docs generate && dbt docs serve
```

---

## 🔎 Decisões técnicas

| Decisão | Alternativa descartada | Motivo |
|---|---|---|
| **MERGE** na Silver/Gold | `TRUNCATE + INSERT` | Idempotência: falha no meio não deixa tabela vazia |
| **`TRY_CAST`** para números | `CAST` direto | Dados do governo têm linhas malformadas; `CAST` quebraria a carga |
| **`ON_ERROR = 'CONTINUE'`** | Parar na primeira linha inválida | Preserva carga parcial; linhas ruins são investigadas depois |
| **`DATE_FROM_PARTS`** | Manter como `VARCHAR` | Permite filtros por range de datas, funções de janela e joins temporais |
| **dbt para Gold** | SP para tudo | dbt gera lineage graph, documentação e testes automatizados — ferramentas de BI entendem melhor |
| **MERGE com `ZEROIFNULL`** | Comparação direta `<>` | `NULL <> NULL` retorna `NULL` em SQL, não `TRUE` — sem isso o MERGE nunca detecta mudanças em campos nulos |

---

## 🧪 Consultas de exemplo

```sql
-- Top 5 ministérios por valor pago (últimos 3 meses)
SELECT orgao_superior, SUM(total_pago) AS total_pago
FROM TB_GOLD_DESPESAS_AGREG
WHERE mes_ano_dt >= DATEADD(month, -3, CURRENT_DATE())
GROUP BY orgao_superior
ORDER BY total_pago DESC
LIMIT 5;

-- Órgãos em alerta crítico (baixa execução + alto RAP)
SELECT * FROM vw_alertas_criticos
WHERE nivel_criticidade = 'CRITICO'
ORDER BY proporcao_restos_pct DESC;

-- Evolução mensal da taxa de execução por ministério
SELECT mes_ano_dt, orgao_superior, taxa_execucao_pct
FROM TB_GOLD_DESPESAS_AGREG
ORDER BY orgao_superior, mes_ano_dt;
```

---

## 🔄 CI/CD

O pipeline de CI/CD roda automaticamente a cada push:

```
push (qualquer branch)
    │
    ▼
✅ validate         ← obrigatório, bloqueia o deploy
   • sqlfluff lint  (estilo e sintaxe SQL)
   • dbt compile    (Jinja + YAML válidos, sem conexão)
   • dbt test       (qualidade dos dados via schema.yml)
    │
    │  somente se validate passou E branch = main
    ▼
🚀 deploy
   • SnowSQL: procedures + tasks
   • dbt run: modelos Gold
```

**Secrets necessários** (Settings → Secrets → Actions):

| Secret | Exemplo |
|---|---|
| `SNOWFLAKE_ACCOUNT` | `MKQAYBK-CK27934` |
| `SNOWFLAKE_USER` | `MARCIOMICHELOTTO` |
| `SNOWFLAKE_PASSWORD` | `****` |
| `SNOWFLAKE_DATABASE` | `DADOS_GOVERNO` |
| `SNOWFLAKE_WAREHOUSE` | `COMPUTE_WH` |
| `SNOWFLAKE_SCHEMA` | `PUBLIC` |
| `SNOWFLAKE_ROLE` | `SYSADMIN` |

---

## 👥 Público-alvo

- Times de dados governamentais e de controle orçamentário
- Analistas de orçamento público e transparência fiscal
- Squads de BI/Analytics com foco em dados do setor público

---

## 🛠️ Stack

![Snowflake](https://img.shields.io/badge/Snowflake-29B5E8?style=flat&logo=snowflake&logoColor=white)
![dbt](https://img.shields.io/badge/dbt-FF694B?style=flat&logo=dbt&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-2088FF?style=flat&logo=github-actions&logoColor=white)
![AWS S3](https://img.shields.io/badge/AWS_S3-FF9900?style=flat&logo=amazon-s3&logoColor=white)
![Python](https://img.shields.io/badge/Python-3776AB?style=flat&logo=python&logoColor=white)
