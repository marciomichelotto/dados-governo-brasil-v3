WITH TOTAIS_GERAIS AS (
    SELECT SUM(valor_pago) AS total_geral
    FROM {{ source('silver', 'TB_SILVER_DESPESAS') }}
    WHERE valor_pago > 0
)
SELECT
    s.orgao_superior AS nome_ministerio,
    COUNT(DISTINCT s.orgao_vinculado) AS qtd_orgaos_vinculados,
    ROUND(SUM(s.valor_empenhado), 2) AS total_empenhado,
    ROUND(SUM(s.valor_liquidado), 2) AS total_liquidado,
    ROUND(SUM(s.valor_pago), 2) AS total_pago,
    ROUND(SUM(s.valor_restos_pagar), 2) AS total_restos,
    ROUND((SUM(s.valor_pago) / tg.total_geral) * 100, 2) AS percentual_do_total,
    RANK() OVER (ORDER BY SUM(s.valor_pago) DESC) AS ranking_pago,
    ROUND((SUM(s.valor_pago) / NULLIF(SUM(s.valor_empenhado), 0)) * 100, 2) AS taxa_execucao
FROM {{ source('silver', 'TB_SILVER_DESPESAS') }} s
CROSS JOIN TOTAIS_GERAIS tg
GROUP BY s.orgao_superior, tg.total_geral
HAVING SUM(s.valor_pago) > 0
ORDER BY total_pago DESC
