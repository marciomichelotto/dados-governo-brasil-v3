-- Camada BRONZE
CREATE OR REPLACE TABLE TB_BRONZE_DESPESAS (
    linha VARIANT
);

CREATE OR REPLACE TABLE TB_BRONZE_DESPESAS_V2 (
    mes_ano              VARCHAR(20),
    orgao_superior       VARCHAR(200),
    orgao_vinculado      VARCHAR(200),
    valor_empenhado      VARCHAR(50),
    valor_liquidado      VARCHAR(50),
    valor_pago           VARCHAR(50),
    valor_restos_pagar   VARCHAR(50)
);

-- Camada SILVER
CREATE OR REPLACE TABLE TB_SILVER_DESPESAS (
    data_referencia      DATE,
    orgao_superior       VARCHAR(200),
    orgao_vinculado      VARCHAR(200),
    valor_empenhado      NUMBER(20,2),
    valor_liquidado      NUMBER(20,2),
    valor_pago           NUMBER(20,2),
    valor_restos_pagar   NUMBER(20,2),
    data_carga           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Camada GOLD
CREATE OR REPLACE TABLE TB_GOLD_DESPESAS_AGREG (
    data_referencia      DATE,
    orgao_superior       VARCHAR(200),
    total_empenhado      NUMBER(20,2),
    total_liquidado      NUMBER(20,2),
    total_pago           NUMBER(20,2),
    total_restos_pagar   NUMBER(20,2),
    data_atualizacao     TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
