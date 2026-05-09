CREATE OR REPLACE PROCEDURE SP_BRONZE_TO_SILVER()
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
    TRUNCATE TABLE TB_SILVER_DESPESAS;

    INSERT INTO TB_SILVER_DESPESAS (
        data_referencia,
        orgao_superior,
        orgao_vinculado,
        valor_empenhado,
        valor_liquidado,
        valor_pago,
        valor_restos_pagar
    )
    SELECT
        DATE_FROM_PARTS(
            2000 + RIGHT(REPLACE(mes_ano, '"', ''), 2),
            CASE LEFT(REPLACE(mes_ano, '"', ''), 3)
                WHEN 'jan' THEN 1 WHEN 'fev' THEN 2 WHEN 'mar' THEN 3
                WHEN 'abr' THEN 4 WHEN 'mai' THEN 5 WHEN 'jun' THEN 6
                WHEN 'jul' THEN 7 WHEN 'ago' THEN 8 WHEN 'set' THEN 9
                WHEN 'out' THEN 10 WHEN 'nov' THEN 11 WHEN 'dez' THEN 12
            END,
            1
        ) AS data_referencia,
        TRIM(REPLACE(orgao_superior, '"', '')) AS orgao_superior,
        TRIM(REPLACE(orgao_vinculado, '"', '')) AS orgao_vinculado,
        TRY_CAST(REPLACE(REPLACE(REPLACE(valor_empenhado, '"', ''), '.', ''), ',', '.') AS NUMBER(20,2)) AS valor_empenhado,
        TRY_CAST(REPLACE(REPLACE(REPLACE(valor_liquidado, '"', ''), '.', ''), ',', '.') AS NUMBER(20,2)) AS valor_liquidado,
        TRY_CAST(REPLACE(REPLACE(REPLACE(valor_pago, '"', ''), '.', ''), ',', '.') AS NUMBER(20,2)) AS valor_pago,
        TRY_CAST(REPLACE(REPLACE(REPLACE(valor_restos_pagar, '"', ''), '.', ''), ',', '.') AS NUMBER(20,2)) AS valor_restos_pagar
    FROM TB_BRONZE_DESPESAS_V2
    WHERE REPLACE(mes_ano, '"', '') IS NOT NULL;

    RETURN 'Silver atualizada com sucesso!';
END;
$$;

CREATE OR REPLACE PROCEDURE SP_SILVER_TO_GOLD()
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
    TRUNCATE TABLE TB_GOLD_DESPESAS_AGREG;

    INSERT INTO TB_GOLD_DESPESAS_AGREG (
        data_referencia,
        orgao_superior,
        total_empenhado,
        total_liquidado,
        total_pago,
        total_restos_pagar
    )
    SELECT
        data_referencia,
        orgao_superior,
        SUM(valor_empenhado),
        SUM(valor_liquidado),
        SUM(valor_pago),
        SUM(valor_restos_pagar)
    FROM TB_SILVER_DESPESAS
    GROUP BY data_referencia, orgao_superior
    ORDER BY data_referencia, orgao_superior;

    RETURN 'Gold agregada com sucesso!';
END;
$$;
