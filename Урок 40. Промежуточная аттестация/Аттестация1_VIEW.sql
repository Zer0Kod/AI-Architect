-- ============================================================
-- Промежуточная аттестация №1
-- База: banking (PostgreSQL)
--
-- Бизнес-задача:
--     снизить потери банка от просроченных платежей по кредитам,
--     выявляя заёмщиков повышенного риска ещё на этапе выдачи,
--     чтобы точечно менять условия (сумму, срок, ставку) или
--     запрашивать дополнительное обеспечение.
--
-- Задача машинного обучения:
--     бинарная классификация. Предсказать, допустит ли заёмщик
--     хотя бы один просроченный платёж в течение срока кредита.
--
-- Зерно представления: один выданный кредит.
--
-- ВАЖНО про утечку целевой переменной:
--     все признаки рассчитываются только по данным, доступным
--     на момент выдачи кредита. Фактическое поведение по
--     платежам в признаки не попадает — иначе модель выучила бы
--     ответ, а не научилась его предсказывать.
-- ============================================================


-- ------------------------------------------------------------
-- Удаление предыдущих версий представлений
-- ------------------------------------------------------------
-- CREATE OR REPLACE не позволяет изменить тип уже существующей
-- колонки представления, поэтому при повторном запуске файла
-- старые версии сначала удаляются.
-- Порядок важен: v_loan_risk опирается на три остальных,
-- поэтому удаляется первым.

DROP VIEW IF EXISTS v_loan_risk;
DROP VIEW IF EXISTS v_loan_employment;
DROP VIEW IF EXISTS v_loan_products;
DROP VIEW IF EXISTS v_loan_target;


-- ------------------------------------------------------------
-- Целевая переменная
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_loan_target AS
SELECT
	lp.loan_id,
	MAX(CASE WHEN ps.status_code IN ('LATE', 'MISSED') THEN 1 ELSE 0 END) AS has_late_payment,
	COUNT(*) AS payments_total
FROM loan_payments AS lp
INNER JOIN loan_payment_statuses AS ps
	ON ps.payment_status_id = lp.payment_status_id
GROUP BY lp.loan_id;


-- ------------------------------------------------------------
-- Занятость и доход на момент выдачи кредита
-- ------------------------------------------------------------
-- Берём запись о занятости, действовавшую на дату выдачи.
-- Более поздние записи использовать нельзя: на момент решения
-- о выдаче банк их ещё не знал.

-- Если у клиента несколько записей о занятости, действовавших на дату
-- выдачи, берём самую свежую из них. Нумеруем записи оконной функцией
-- внутри каждого кредита и оставляем первую.

CREATE OR REPLACE VIEW v_loan_employment AS
WITH ranked_employment AS (
		SELECT
			l.loan_id,
			ce.annual_income,
			es.status_name AS employment_status,
			ind.industry_name,
			ROW_NUMBER() OVER (
				PARTITION BY l.loan_id
				ORDER BY ce.valid_from DESC
			) AS row_num
		FROM loans AS l
		INNER JOIN customer_employment AS ce
			ON ce.customer_id = l.customer_id
			AND ce.valid_from <= l.disbursement_date
			AND (ce.valid_to IS NULL OR ce.valid_to > l.disbursement_date)
		LEFT JOIN employment_statuses AS es
			ON es.employment_status_id = ce.employment_status_id
		LEFT JOIN industries AS ind
			ON ind.industry_id = ce.industry_id
	)

SELECT
	loan_id,
	annual_income,
	employment_status,
	industry_name
FROM ranked_employment
WHERE row_num = 1;


-- ------------------------------------------------------------
-- Продуктовая активность клиента на момент выдачи
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_loan_products AS
SELECT
	l.loan_id,
	COUNT(DISTINCT a.account_id) AS accounts_count,
	COUNT(DISTINCT c.card_id)    AS cards_count
FROM loans AS l
LEFT JOIN accounts AS a
	ON a.customer_id = l.customer_id
	AND a.opened_at <= l.disbursement_date
LEFT JOIN cards AS c
	ON c.account_id = a.account_id
	AND c.issued_at <= l.disbursement_date
GROUP BY l.loan_id;


-- ------------------------------------------------------------
-- Основное представление
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_loan_risk AS
SELECT
	l.loan_id,
	l.customer_id,

	-- ЦЕЛЕВАЯ ПЕРЕМЕННАЯ
	t.has_late_payment,

	-- ПРИЗНАКИ: параметры самого кредита
	l.principal_amount,
	l.interest_rate,
	l.term_months,
	lpr.loan_type,
	lpr.product_name AS loan_product,

	-- ПРИЗНАК: оценка ежемесячного платежа
	-- Упрощённая оценка: тело плюс проценты за весь срок,
	-- делённые на число месяцев.
	CAST(
		l.principal_amount * (1 + l.interest_rate / 100.0 * l.term_months / 12.0)
		/ NULLIF(l.term_months, 0)
		AS NUMERIC(14,2)
	) AS monthly_payment_est,

	-- ПРИЗНАКИ: заёмщик
	e.annual_income,
	e.employment_status,
	e.industry_name,

	-- ПРИЗНАК: долговая нагрузка (сумма кредита к годовому доходу)
	CAST(
		l.principal_amount / NULLIF(e.annual_income, 0)
		AS NUMERIC(12,4)
	) AS debt_to_income,

	-- ПРИЗНАК: доля ежемесячного платежа в месячном доходе
	CAST(
		l.principal_amount * (1 + l.interest_rate / 100.0 * l.term_months / 12.0)
		/ NULLIF(l.term_months, 0)
		/ NULLIF(e.annual_income / 12.0, 0)
		AS NUMERIC(12,4)
	) AS payment_to_income,

	-- ПРИЗНАК: возраст заёмщика на момент выдачи, лет
	-- Обе даты имеют тип DATE, и их разность сразу даёт число дней,
	-- поэтому достаточно поделить её на среднюю длину года.
	CAST(
		(l.disbursement_date - cu.date_of_birth) / 365.25
		AS NUMERIC(6,1)
	) AS borrower_age_years,

	-- ПРИЗНАК: стаж клиента в банке на момент выдачи, лет
	CAST(
		(l.disbursement_date - cu.registration_date) / 365.25
		AS NUMERIC(8,2)
	) AS client_tenure_years,

	-- ПРИЗНАКИ: продуктовая активность
	p.accounts_count,
	p.cards_count,

	-- служебные поля, в модель не идут
	l.disbursement_date,
	t.payments_total

FROM loans AS l
INNER JOIN v_loan_target AS t
	ON t.loan_id = l.loan_id
INNER JOIN loan_products AS lpr
	ON lpr.loan_product_id = l.loan_product_id
INNER JOIN customers AS cu
	ON cu.customer_id = l.customer_id
LEFT JOIN v_loan_employment AS e
	ON e.loan_id = l.loan_id
LEFT JOIN v_loan_products AS p
	ON p.loan_id = l.loan_id;


-- ------------------------------------------------------------
-- Проверка
-- ------------------------------------------------------------
SELECT
	COUNT(*) AS rows_in_view,
	SUM(has_late_payment) AS with_late,
	CAST(AVG(has_late_payment) * 100 AS NUMERIC(5,2)) AS late_pct
FROM v_loan_risk;

SELECT * FROM v_loan_risk ORDER BY loan_id LIMIT 5;
