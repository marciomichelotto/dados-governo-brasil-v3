WITH METRICAS_CRITICAS AS (
    SELECT
        s.orgao_superior AS nome_ministerio,
        s.orgao_vinculado,
        s.data_referencia,
        ROUND(SUM(s.valor_empenhado), 2) AS empenhado_mes,
        ROUND(SUM(s.valor_restos_pagar), 2) AS restos_mes,
        ROUND((SUM(s.valor_restos_pagar) / NULLIF(SUM(s.valor_empenhado), 0)) * 100, 2) AS percentual_restos,
        SUM(CASE WHEN s.valor_empenhado < 0 THEN 1 ELSE 0 END) AS qtd_empenhos_negativos
    FROM {{ ref('tb_silver_despesas') }} s
    GROUP BY s.orgao_superior, s.orgao_vinculado, s.data_referencia
)
SELECT
    nome_ministerio,
    orgao_vinculado,
    data_referencia AS mes_critico,
    empenhado_mes,
    restos_mes,
    percentual_restos,
    qtd_empenhos_negativos,
    CASE
        WHEN percentual_restos > 100 THEN '🚨 CRÍTICO ABSOLUTO'
        WHEN percentual_restos > 50 THEN '🔴 ALERTA MÁXIMO'
        WHEN percentual_restos > 25 THEN '🟠 ALERTA MODERADO'
        ELSE '🟡 MONITORAMENTO'
    END AS nivel_critico,
    CASE
        WHEN percentual_restos > 100 THEN 'Revisão urgente: restos maiores que empenhos'
        WHEN percentual_restos > 50 THEN 'Necessário plano de quitação imediato'
        WHEN percentual_restos > 25 THEN 'Acompanhamento semanal obrigatório'
        ELSE 'Monitoramento mensal'
    END AS acao_recomendada,
    RANK() OVER (ORDER BY percentual_restos DESC) AS ranking_criticidade
FROM METRICAS_CRITICAS
WHERE percentual_restos > 25
  AND empenhado_mes != 0
ORDER BY percentual_restos DESC
