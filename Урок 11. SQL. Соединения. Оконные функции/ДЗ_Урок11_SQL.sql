-- ============================================================
-- Домашнее задание. Урок 11
-- Язык запросов SQL. Операторы соединения. Оконные функции
-- Учебная база: dvdrental (PostgreSQL)
--
-- Для каждого фильма посчитать:
--   1) количество уникальных клиентов, бравших его в прокат
--   2) сумму денег, которую он принёс
--   3) среднюю продолжительность проката
--   4) долю просроченных прокатов
--   5) количество клиентов, бравших фильм повторно
-- ============================================================


-- ------------------------------------------------------------
-- Особенности данных, которые определили структуру запроса
-- ------------------------------------------------------------
-- Перед написанием запроса имеет смысл проверить три вещи,
-- каждая из которых способна незаметно исказить результат.

SELECT
	'фильмов всего' AS check_name,
	CAST(COUNT(*) AS TEXT) AS value
FROM film

UNION ALL

SELECT
	'фильмов без inventory',
	CAST(COUNT(*) AS TEXT)
FROM film AS f
LEFT JOIN inventory AS i ON i.film_id = f.film_id
WHERE i.inventory_id IS NULL

UNION ALL

SELECT
	'прокатов без return_date',
	CAST(COUNT(*) AS TEXT)
FROM rental
WHERE return_date IS NULL

UNION ALL

SELECT
	'макс. платежей на прокат',
	CAST(MAX(cnt) AS TEXT)
FROM (
		SELECT
			rental_id,
			COUNT(*) AS cnt
		FROM payment
		GROUP BY rental_id
	) AS p;

-- Результат:
--   фильмов всего             1000
--   фильмов без inventory       42   -> нужен LEFT JOIN, иначе они пропадут
--   прокатов без return_date   183   -> их нельзя считать в длительности
--   макс. платежей на прокат     5   -> payment нельзя присоединять напрямую,
--                                       иначе строки размножатся


-- ------------------------------------------------------------
-- Основной запрос
-- ------------------------------------------------------------

WITH film_rentals AS (
		-- Раскрываем цепочку film -> inventory -> rental.
		-- LEFT JOIN, потому что нужны все фильмы, включая те,
		-- которые ни разу не выдавались.
		SELECT
			f.film_id,
			f.title,
			f.rental_duration,
			r.rental_id,
			r.customer_id,
			r.rental_date,
			r.return_date
		FROM film AS f
		LEFT JOIN inventory AS i ON i.film_id = f.film_id
		LEFT JOIN rental AS r ON r.inventory_id = i.inventory_id
	),

	revenue AS (
		-- Выручка считается отдельно. Если присоединить payment
		-- к основному набору, прокаты с несколькими платежами
		-- продублируют строки и испортят все остальные счётчики.
		SELECT
			fr.film_id,
			SUM(p.amount) AS total_amount
		FROM film_rentals AS fr
		INNER JOIN payment AS p ON p.rental_id = fr.rental_id
		GROUP BY fr.film_id
	),

	repeat_pairs AS (
		-- Пары «фильм — клиент», где клиент брал этот фильм
		-- более одного раза.
		SELECT
			film_id,
			customer_id
		FROM film_rentals
		WHERE rental_id IS NOT NULL
		GROUP BY film_id, customer_id
		HAVING COUNT(rental_id) > 1
	),

	repeat_stat AS (
		-- Сколько таких клиентов у каждого фильма.
		SELECT
			film_id,
			COUNT(customer_id) AS repeat_customers
		FROM repeat_pairs
		GROUP BY film_id
	),

	metrics AS (
		-- Показатели, которые считаются по самим прокатам.
		SELECT
			film_id,
			title,
			COUNT(DISTINCT customer_id) AS unique_customers,
			COUNT(rental_id)            AS rentals_total,
			COUNT(return_date)          AS rentals_returned,
			AVG(EXTRACT(EPOCH FROM (return_date - rental_date)) / 86400) AS avg_days,
			SUM(
				CASE
					WHEN return_date > rental_date + rental_duration * INTERVAL '1 day'
						THEN 1
					ELSE 0
				END
			) AS overdue_count
		FROM film_rentals
		GROUP BY film_id, title
	)

SELECT
	m.film_id,
	m.title,
	m.unique_customers,
	CASE
		WHEN rv.total_amount IS NULL THEN 0
		ELSE rv.total_amount
	END AS total_amount,
	CAST(m.avg_days AS NUMERIC(6,2)) AS avg_rental_days,
	CASE
		WHEN m.rentals_returned = 0 THEN NULL
		ELSE CAST(m.overdue_count * 1.0 / m.rentals_returned AS NUMERIC(4,3))
	END AS overdue_share,
	CASE
		WHEN rs.repeat_customers IS NULL THEN 0
		ELSE rs.repeat_customers
	END AS repeat_customers
FROM metrics AS m
LEFT JOIN revenue AS rv ON rv.film_id = m.film_id
LEFT JOIN repeat_stat AS rs ON rs.film_id = m.film_id
ORDER BY total_amount DESC, m.title;


-- ------------------------------------------------------------
-- Пояснения к отдельным показателям
-- ------------------------------------------------------------
-- 1) Уникальные клиенты: COUNT(DISTINCT customer_id).
--    Один клиент, взявший фильм трижды, считается один раз.
--
-- 3) Средняя продолжительность: разность двух timestamp даёт
--    интервал, поэтому он переводится в секунды через EXTRACT
--    и делится на 86400, чтобы получить дни числом.
--    Невозвращённые прокаты дают NULL и в среднее не попадают —
--    это корректно, их длительность просто неизвестна.
--
-- 4) Доля просрочки: делим на rentals_returned, а не на
--    rentals_total. Невозвращённый фильм нельзя назвать ни
--    просроченным, ни возвращённым вовремя.
--    Деление на ноль закрыто через CASE: если возвратов не было,
--    доля не определена и выводится NULL, а не 0.
--
-- 5) Повторные клиенты: сначала группируем по паре
--    «фильм — клиент» и оставляем пары с числом прокатов
--    больше одного, затем считаем их по фильму.


-- ------------------------------------------------------------
-- Дополнительно: оконная функция
-- ------------------------------------------------------------
-- Тема урока включает оконные функции, поэтому покажем,
-- как выглядит рейтинг фильмов по выручке внутри категории.
-- Оконная функция не схлопывает строки: рядом с каждым фильмом
-- остаётся и его собственная выручка, и средняя по категории.

WITH film_revenue AS (
		SELECT
			f.film_id,
			f.title,
			c.name AS category,
			SUM(p.amount) AS total_amount
		FROM film AS f
		INNER JOIN film_category AS fc ON fc.film_id = f.film_id
		INNER JOIN category AS c ON c.category_id = fc.category_id
		INNER JOIN inventory AS i ON i.film_id = f.film_id
		INNER JOIN rental AS r ON r.inventory_id = i.inventory_id
		INNER JOIN payment AS p ON p.rental_id = r.rental_id
		GROUP BY f.film_id, f.title, c.name
	)

SELECT
	category,
	title,
	total_amount,
	RANK() OVER (PARTITION BY category ORDER BY total_amount DESC) AS rank_in_category,
	CAST(AVG(total_amount) OVER (PARTITION BY category) AS NUMERIC(8,2)) AS category_avg
FROM film_revenue
ORDER BY category, rank_in_category
LIMIT 20;
