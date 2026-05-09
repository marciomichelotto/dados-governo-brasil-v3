# Dados Governo Brasil v3

Pipeline de dados em **Snowflake** + **dbt** para ingestão, tratamento e análise de despesas públicas em arquitetura **Medallion (Bronze → Silver → Gold)**.

## 🎯 Objetivo

Este projeto organiza o fluxo de dados de despesas por órgão para permitir:

- ingestão bruta confiável (Bronze);
- padronização e tipagem de dados (Silver);
- geração de visões analíticas e indicadores executivos (Gold).

## 🧱 Arquitetura

### Bronze
Camada de entrada dos dados sem regras complexas de negócio.

- `TB_BRONZE_DESPESAS`: armazenamento bruto em `VARIANT`.
- `TB_BRONZE_DESPESAS_V2`: staging estruturado em `VARCHAR` para carga CSV/TSV.

### Silver
Camada de qualidade e padronização.

- Conversão de `mes_ano` (ex.: `mar/25`) para `DATE`;
- limpeza de aspas e espaços;
- conversão de números no padrão brasileiro (milhar `.` e decimal `,`) para `NUMBER(20,2)`.

Tabela principal:

- `TB_SILVER_DESPESAS`

### Gold
Camada analítica para consumo por BI e relatórios.

- `TB_GOLD_DESPESAS_AGREG`: agregações por mês e órgão superior.
- Views analíticas em dbt:
  - `vw_ranking_ministerios`
  - `vw_restos_a_pagar`
  - `vw_execucao_orcamentaria`
  - `vw_alertas_criticos`

## 📁 Estrutura do repositório

```text
snowflake/
  setup/
    01_database.sql
    02_stage.sql
    03_tables.sql
  procedures/
    sp_bronze_load.sql
    sp_silver_clean.sql
  tasks/
    orchestration.sql

dbt/
  dbt_project.yml
  schema.yml
  models/
    gold/
      vw_ranking_ministerios.sql
      vw_restos_a_pagar.sql
      vw_execucao_orcamentaria.sql
      vw_alertas_criticos.sql
```

## ⚙️ Pré-requisitos

- Conta Snowflake com permissões para criar objetos (DB, schema, stage, file format, tabelas, procedures e tasks).
- Warehouse ativo (exemplo usado: `COMPUTE_WH`).
- Stage externo configurado (`@AWS_STAGE`) contendo o arquivo:
  - `despesasPorOrgao(in).csv`
- dbt instalado e perfil configurado para Snowflake.

## 🚀 Execução (ordem sugerida)

### 1) Setup inicial no Snowflake

Execute, nesta ordem:

1. `snowflake/setup/01_database.sql`
2. `snowflake/setup/02_stage.sql`
3. `snowflake/setup/03_tables.sql`

### 2) Carga Bronze

Execute:

- `snowflake/procedures/sp_bronze_load.sql`

### 3) Transformações

Execute:

- `snowflake/procedures/sp_silver_clean.sql` (cria procedures)
- `CALL SP_BRONZE_TO_SILVER();`
- `CALL SP_SILVER_TO_GOLD();`

### 4) Orquestração automática

Execute:

- `snowflake/tasks/orchestration.sql`

Isso criará a cadeia:

- `TASK_CARREGA_BRONZE` (agendada via CRON)
- `TASK_BRONZE_TO_SILVER` (AFTER Bronze)
- `TASK_SILVER_TO_GOLD` (AFTER Silver)

## 📊 Modelos analíticos (dbt)

Após ter a Silver populada, rode os modelos Gold:

```bash
dbt run --select gold
```

Validação recomendada:

```bash
dbt test
```

## 🧪 Consultas de exemplo

- Top 5 ministérios por valor pago.
- Órgãos com maior volume de restos a pagar.
- Classificação de eficiência de execução orçamentária.
- Alertas críticos por mês/órgão vinculado.

## 🔎 Regras importantes de transformação

- **Datas:** `mes_ano` é convertido para o primeiro dia do mês (`DATE_FROM_PARTS`).
- **Números:** limpeza de aspas, remoção de separador de milhar e troca de vírgula decimal por ponto antes de `TRY_CAST`.
- **Resiliência de carga:** `COPY INTO ... ON_ERROR = 'CONTINUE'` para evitar interrupção total por linhas inválidas.

## 🛠️ Próximas melhorias sugeridas

- Implementar carga incremental (evitando `TRUNCATE` completo na Silver/Gold).
- Adicionar testes dbt de qualidade (unicidade, not null e accepted values).
- Criar documentação dbt (`dbt docs generate`) com descrição de colunas.
- Adicionar monitoramento de falhas em tasks e alertas operacionais.

## 👥 Público-alvo

- Times de dados governamentais;
- analistas de orçamento público;
- squads de BI/analytics com foco em transparência fiscal.

---

Se quiser, no próximo passo posso te entregar também:

1. um `schema.yml` completo com testes;
2. um `Makefile` para execução padronizada;
3. um guia rápido de dashboard (Power BI / Looker Studio) baseado nas views Gold.
