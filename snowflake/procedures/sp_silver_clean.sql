-- =============================================================================
-- SP_BRONZE_TO_SILVER  |  Carga incremental com MERGE (idempotente)
-- Projeto  : dados-governo-brasil-v3
-- Camada   : Bronze → Silver
-- Autor    : Marcio Michelotto
-- Versão   : 2.0  (substitui TRUNCATE + INSERT por MERGE)
--
-- POR QUE MERGE E NÃO TRUNCATE?
--   • Idempotência: rodar duas vezes não corrompe dados
--   • Se o pipeline falhar no meio, Silver não fica vazia
--   • Permite rastrear linhas novas vs. atualizadas via SYSTEM$STREAM
--   • Base para implementar SCD Type 2 no futuro sem reescrever tudo
-- =============================================================================

CREATE OR REPLACE PROCEDURE SP_BRONZE_TO_SILVER()
RETURNS VARIANT
LANGUAGE SQL
AS
$$
DECLARE
    v_inicio        TIMESTAMP_NTZ := CURRENT_TIMESTAMP();
    v_rows_inserted NUMBER        := 0;
    v_rows_updated  NUMBER        := 0;
    v_rows_errors   NUMBER        := 0;
    v_resultado     VARIANT;
BEGIN

    -- -------------------------------------------------------------------------
    -- STEP 1: Staging temporário com limpeza e tipagem dos dados Bronze
    --         Isolamos a transformação aqui para que o MERGE seja legível
    -- -------------------------------------------------------------------------
    CREATE OR REPLACE TEMPORARY TABLE TMP_SILVER_STAGING AS
    SELECT
        -- Chave natural: combinação mês/ano + órgão subordinado
        -- Usada como chave de upsert no MERGE abaixo
        TRIM(orgao_subordinado_cod)                          AS orgao_subordinado_cod,

        -- Conversão de mes_ano (ex: "mar/25") para DATE (primeiro dia do mês)
        -- TRY_TO_DATE retorna NULL em vez de explodir em valores inválidos
        TRY_TO_DATE(
            '01/' || REPLACE(TRIM(mes_ano), '/', '/20'),
            'DD/MM/YYYY'
        )                                                    AS mes_ano_dt,

        -- Limpeza de texto
        TRIM(orgao_superior_descricao)                       AS orgao_superior,
        TRIM(orgao_subordinado_descricao)                    AS orgao_subordinado,

        -- Conversão numérica: padrão BR (1.234,56) → NUMBER
        -- Sequência: remove aspas → remove ponto de milhar → troca vírgula por ponto
        TRY_CAST(
            REPLACE(
                REPLACE(
                    REPLACE(TRIM(valor_empenhado), '"', ''),
                '.',  ''),
            ',', '.') AS NUMBER(20, 2)
        )                                                    AS valor_empenhado,

        TRY_CAST(
            REPLACE(
                REPLACE(
                    REPLACE(TRIM(valor_liquidado), '"', ''),
                '.',  ''),
            ',', '.') AS NUMBER(20, 2)
        )                                                    AS valor_liquidado,

        TRY_CAST(
            REPLACE(
                REPLACE(
                    REPLACE(TRIM(valor_pago), '"', ''),
                '.',  ''),
            ',', '.') AS NUMBER(20, 2)
        )                                                    AS valor_pago,

        TRY_CAST(
            REPLACE(
                REPLACE(
                    REPLACE(TRIM(restos_a_pagar_inscritos), '"', ''),
                '.',  ''),
            ',', '.') AS NUMBER(20, 2)
        )                                                    AS restos_a_pagar_inscritos,

        TRY_CAST(
            REPLACE(
                REPLACE(
                    REPLACE(TRIM(restos_a_pagar_pagos), '"', ''),
                '.',  ''),
            ',', '.') AS NUMBER(20, 2)
        )                                                    AS restos_a_pagar_pagos,

        -- Metadados de auditoria (rastreabilidade da carga)
        CURRENT_TIMESTAMP()                                  AS dt_carga_silver,
        METADATA$FILENAME                                    AS arquivo_origem

    FROM TB_BRONZE_DESPESAS_V2

    -- Filtra somente linhas com chave válida
    -- (mes_ano e orgao_subordinado_cod são obrigatórios para o MERGE funcionar)
    WHERE TRIM(mes_ano) IS NOT NULL
      AND TRIM(orgao_subordinado_cod) IS NOT NULL;


    -- -------------------------------------------------------------------------
    -- STEP 2: MERGE — upsert na Silver
    --
    --   WHEN MATCHED     → atualiza se algum valor numérico mudou
    --   WHEN NOT MATCHED → insere linha nova
    --
    -- Chave de negócio: (orgao_subordinado_cod + mes_ano_dt)
    -- Garante que a mesma competência/órgão não seja duplicada
    -- -------------------------------------------------------------------------
    MERGE INTO TB_SILVER_DESPESAS AS tgt
    USING (
        SELECT * FROM TMP_SILVER_STAGING
        WHERE mes_ano_dt IS NOT NULL   -- descarta conversões de data inválidas
    ) AS src
        ON  tgt.orgao_subordinado_cod = src.orgao_subordinado_cod
        AND tgt.mes_ano_dt            = src.mes_ano_dt

    WHEN MATCHED AND (
        -- Só atualiza se houve mudança real (evita writes desnecessários)
        ZEROIFNULL(tgt.valor_pago)                 <> ZEROIFNULL(src.valor_pago)
        OR ZEROIFNULL(tgt.valor_liquidado)         <> ZEROIFNULL(src.valor_liquidado)
        OR ZEROIFNULL(tgt.valor_empenhado)         <> ZEROIFNULL(src.valor_empenhado)
        OR ZEROIFNULL(tgt.restos_a_pagar_inscritos)<> ZEROIFNULL(src.restos_a_pagar_inscritos)
        OR ZEROIFNULL(tgt.restos_a_pagar_pagos)   <> ZEROIFNULL(src.restos_a_pagar_pagos)
    )
    THEN UPDATE SET
        tgt.orgao_superior              = src.orgao_superior,
        tgt.orgao_subordinado           = src.orgao_subordinado,
        tgt.valor_empenhado             = src.valor_empenhado,
        tgt.valor_liquidado             = src.valor_liquidado,
        tgt.valor_pago                  = src.valor_pago,
        tgt.restos_a_pagar_inscritos    = src.restos_a_pagar_inscritos,
        tgt.restos_a_pagar_pagos        = src.restos_a_pagar_pagos,
        tgt.dt_atualizacao_silver       = CURRENT_TIMESTAMP(),
        tgt.arquivo_origem              = src.arquivo_origem

    WHEN NOT MATCHED THEN INSERT (
        orgao_subordinado_cod,
        mes_ano_dt,
        orgao_superior,
        orgao_subordinado,
        valor_empenhado,
        valor_liquidado,
        valor_pago,
        restos_a_pagar_inscritos,
        restos_a_pagar_pagos,
        dt_carga_silver,
        dt_atualizacao_silver,
        arquivo_origem
    ) VALUES (
        src.orgao_subordinado_cod,
        src.mes_ano_dt,
        src.orgao_superior,
        src.orgao_subordinado,
        src.valor_empenhado,
        src.valor_liquidado,
        src.valor_pago,
        src.restos_a_pagar_inscritos,
        src.restos_a_pagar_pagos,
        src.dt_carga_silver,
        CURRENT_TIMESTAMP(),
        src.arquivo_origem
    );


    -- -------------------------------------------------------------------------
    -- STEP 3: Captura de métricas pós-MERGE
    -- -------------------------------------------------------------------------
    -- Snowflake não expõe rows_inserted/rows_updated diretamente após MERGE,
    -- mas podemos capturar via query_history ou simplesmente logar o timestamp.
    -- Para projetos futuros: considere uma tabela de log de execuções.

    v_resultado := OBJECT_CONSTRUCT(
        'status',       'SUCCESS',
        'procedure',    'SP_BRONZE_TO_SILVER',
        'inicio',       v_inicio::VARCHAR,
        'fim',          CURRENT_TIMESTAMP()::VARCHAR,
        'observacao',   'MERGE concluído. Verifique TB_SILVER_DESPESAS.'
    );

    RETURN v_resultado;

EXCEPTION
    WHEN OTHER THEN
        RETURN OBJECT_CONSTRUCT(
            'status',    'ERROR',
            'procedure', 'SP_BRONZE_TO_SILVER',
            'mensagem',  SQLERRM,
            'sqlcode',   SQLCODE::VARCHAR,
            'inicio',    v_inicio::VARCHAR,
            'fim',       CURRENT_TIMESTAMP()::VARCHAR
        );
END;
$$;


-- =============================================================================
-- SP_SILVER_TO_GOLD  |  Carga incremental com MERGE (idempotente)
-- Camada: Silver → Gold
--
-- POR QUE MERGE AQUI TAMBÉM?
--   • TB_GOLD_DESPESAS_AGREG é consumida por BI/dashboards em tempo real
--   • TRUNCATE interrompe queries em andamento (lock table)
--   • MERGE aplica apenas o delta, mais rápido e seguro
-- =============================================================================

CREATE OR REPLACE PROCEDURE SP_SILVER_TO_GOLD()
RETURNS VARIANT
LANGUAGE SQL
AS
$$
DECLARE
    v_inicio    TIMESTAMP_NTZ := CURRENT_TIMESTAMP();
    v_resultado VARIANT;
BEGIN

    -- -------------------------------------------------------------------------
    -- STEP 1: Agrega Silver por mês e órgão superior
    --         Chave de negócio na Gold: (mes_ano_dt + orgao_superior)
    -- -------------------------------------------------------------------------
    MERGE INTO TB_GOLD_DESPESAS_AGREG AS tgt
    USING (
        SELECT
            mes_ano_dt,
            orgao_superior,

            -- Agregações principais
            SUM(valor_empenhado)            AS total_empenhado,
            SUM(valor_liquidado)            AS total_liquidado,
            SUM(valor_pago)                 AS total_pago,
            SUM(restos_a_pagar_inscritos)   AS total_restos_inscritos,
            SUM(restos_a_pagar_pagos)       AS total_restos_pagos,

            -- KPIs derivados calculados na Gold (não na Silver)
            -- Taxa de execução: quanto do empenhado foi efetivamente pago
            CASE
                WHEN SUM(valor_empenhado) > 0
                THEN ROUND(SUM(valor_pago) / SUM(valor_empenhado) * 100, 2)
                ELSE 0
            END                             AS taxa_execucao_pct,

            -- Proporção de restos a pagar sobre o total pago
            CASE
                WHEN SUM(valor_pago) > 0
                THEN ROUND(SUM(restos_a_pagar_inscritos) / SUM(valor_pago) * 100, 2)
                ELSE 0
            END                             AS proporcao_restos_pct,

            COUNT(DISTINCT orgao_subordinado_cod)   AS qtd_orgaos_subordinados,
            CURRENT_TIMESTAMP()                     AS dt_carga_gold

        FROM TB_SILVER_DESPESAS
        WHERE mes_ano_dt IS NOT NULL
          AND orgao_superior IS NOT NULL
        GROUP BY mes_ano_dt, orgao_superior

    ) AS src
        ON  tgt.mes_ano_dt     = src.mes_ano_dt
        AND tgt.orgao_superior = src.orgao_superior

    WHEN MATCHED AND (
        ZEROIFNULL(tgt.total_pago)      <> ZEROIFNULL(src.total_pago)
        OR ZEROIFNULL(tgt.total_empenhado) <> ZEROIFNULL(src.total_empenhado)
    )
    THEN UPDATE SET
        tgt.total_empenhado         = src.total_empenhado,
        tgt.total_liquidado         = src.total_liquidado,
        tgt.total_pago              = src.total_pago,
        tgt.total_restos_inscritos  = src.total_restos_inscritos,
        tgt.total_restos_pagos      = src.total_restos_pagos,
        tgt.taxa_execucao_pct       = src.taxa_execucao_pct,
        tgt.proporcao_restos_pct    = src.proporcao_restos_pct,
        tgt.qtd_orgaos_subordinados = src.qtd_orgaos_subordinados,
        tgt.dt_atualizacao_gold     = CURRENT_TIMESTAMP()

    WHEN NOT MATCHED THEN INSERT (
        mes_ano_dt,
        orgao_superior,
        total_empenhado,
        total_liquidado,
        total_pago,
        total_restos_inscritos,
        total_restos_pagos,
        taxa_execucao_pct,
        proporcao_restos_pct,
        qtd_orgaos_subordinados,
        dt_carga_gold,
        dt_atualizacao_gold
    ) VALUES (
        src.mes_ano_dt,
        src.orgao_superior,
        src.total_empenhado,
        src.total_liquidado,
        src.total_pago,
        src.total_restos_inscritos,
        src.total_restos_pagos,
        src.taxa_execucao_pct,
        src.proporcao_restos_pct,
        src.qtd_orgaos_subordinados,
        src.dt_carga_gold,
        CURRENT_TIMESTAMP()
    );

    v_resultado := OBJECT_CONSTRUCT(
        'status',     'SUCCESS',
        'procedure',  'SP_SILVER_TO_GOLD',
        'inicio',     v_inicio::VARCHAR,
        'fim',        CURRENT_TIMESTAMP()::VARCHAR,
        'observacao', 'MERGE concluído. Verifique TB_GOLD_DESPESAS_AGREG.'
    );

    RETURN v_resultado;

EXCEPTION
    WHEN OTHER THEN
        RETURN OBJECT_CONSTRUCT(
            'status',    'ERROR',
            'procedure', 'SP_SILVER_TO_GOLD',
            'mensagem',  SQLERRM,
            'sqlcode',   SQLCODE::VARCHAR,
            'inicio',    v_inicio::VARCHAR,
            'fim',       CURRENT_TIMESTAMP()::VARCHAR
        );
END;
$$;


-- =============================================================================
-- COMO TESTAR (quando o Snowflake estiver disponível)
-- =============================================================================
--
--   CALL SP_BRONZE_TO_SILVER();
--   CALL SP_SILVER_TO_GOLD();
--
-- Verificação pós-execução:
--   SELECT COUNT(*), MAX(dt_carga_silver) FROM TB_SILVER_DESPESAS;
--   SELECT COUNT(*), MAX(dt_carga_gold)   FROM TB_GOLD_DESPESAS_AGREG;
--
-- Para simular uma recarga (idempotência):
--   CALL SP_BRONZE_TO_SILVER();   -- rodar 2x deve retornar o mesmo resultado
--   SELECT COUNT(*) FROM TB_SILVER_DESPESAS;  -- contagem não deve dobrar
-- =============================================================================
