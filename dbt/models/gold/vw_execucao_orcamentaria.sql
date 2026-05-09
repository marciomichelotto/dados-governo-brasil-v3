WITH EXECUCAO_MENSAL AS (
    SELECT
        s.orgao_superior AS nome_ministerio,
        s.data_referencia,
        ROUND(SUM(s.valor_empenhado), 2) AS empenhado_mes,
        ROUND(SUM(s.valor_liquidado), 2) AS liquidado_mes,
        ROUND(SUM(s.valor_pago), 2) AS pago_mes,
        ROUND(SUM(s.valor_restos_pagar), 2) AS restos_mes,
        ROUND((SUM(s.valor_pago) / NULLIF(SUM(s.valor_empenhado), 0)) * 100, 2) AS execucao_mensal,
        ROUND((SUM(s.valor_liquidado) / NULLIF(SUM(s.valor_empenhado), 0)) * 100, 2) AS liquidacao_mensal,
        ROUND((SUM(s.valor_pago) / NULLIF(SUM(s.valor_liquidado), 0)) * 100, 2) AS eficiencia_pagamento
    FROM {{ ref('tb_silver_despesas') }} s
    GROUP BY s.orgao_superior, s.data_referencia
)
SELECT
    nome_ministerio,
    COUNT(DISTINCT data_referencia) AS meses_com_dados,
    ROUND(AVG(empenhado_mes), 2) AS media_empenhado_mensal,
    ROUND(AVG(pago_mes), 2) AS media_pago_mensal,
    ROUND(AVG(execucao_mensal), 2) AS taxa_execucao_media,
    ROUND(AVG(eficiencia_pagamento), 2) AS eficiencia_pagamento_media,
    MAX(execucao_mensal) AS melhor_execucao_mensal,
    MIN(execucao_mensal) AS pior_execucao_mensal,
    CASE
        WHEN AVG(execucao_mensal) >= 80 THEN 'Excelente'
        WHEN AVG(execucao_mensal) >= 60 THEN 'Bom'
        WHEN AVG(execucao_mensal) >= 40 THEN 'Regular'
        WHEN AVG(execucao_mensal) >= 20 THEN 'Ruim'
        ELSE 'Crítico'
    END AS classificacao_eficiencia
FROM EXECUCAO_MENSAL
GROUP BY nome_ministerio
HAVING COUNT(DISTINCT data_referencia) >= 6
ORDER BY taxa_execucao_media DESC
