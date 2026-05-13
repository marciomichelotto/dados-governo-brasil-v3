WITH RESTOS_POR_MINISTERIO AS (
    SELECT
        s.orgao_superior AS nome_ministerio,
        COUNT(DISTINCT s.orgao_vinculado) AS orgaos_com_restos,
        ROUND(SUM(s.valor_restos_pagar), 2) AS total_restos_acumulados,
        ROUND(SUM(s.valor_empenhado), 2) AS total_empenhado,
        ROUND((SUM(s.valor_restos_pagar) / NULLIF(SUM(s.valor_empenhado), 0)) * 100, 2) AS percentual_empenhado_restos,
        MIN(s.data_referencia) AS primeiro_mes_restos,
        MAX(s.data_referencia) AS ultimo_mes_restos
    FROM {{ source('silver', 'TB_SILVER_DESPESAS') }} s
    WHERE s.valor_restos_pagar > 0
    GROUP BY s.orgao_superior
)
SELECT
    nome_ministerio,
    orgaos_com_restos,
    total_restos_acumulados,
    total_empenhado,
    percentual_empenhado_restos,
    primeiro_mes_restos,
    ultimo_mes_restos,
    CASE
        WHEN percentual_empenhado_restos > 50 THEN 'Risco Extremo'
        WHEN percentual_empenhado_restos > 30 THEN 'Risco Alto'
        WHEN percentual_empenhado_restos > 15 THEN 'Risco Médio'
        ELSE 'Risco Baixo'
    END AS nivel_risco,
    RANK() OVER (ORDER BY total_restos_acumulados DESC) AS ranking_divida
FROM RESTOS_POR_MINISTERIO
ORDER BY total_restos_acumulados DESC
