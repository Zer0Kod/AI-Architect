-- ============================================================
-- Домашнее задание. Урок 12
-- Язык запросов SQL. Индексация. Нагрузочное тестирование
-- Учебная база: dvdrental (PostgreSQL)
--
-- Практическая задача:
--   Для каждой страны определить ключевых клиентов — кто
--   приносит основную выручку на своём рынке. Результат нужен
--   для адресных программ лояльности: скидки и персональные
--   предложения имеет смысл давать не «всем подряд», а тем,
--   кто уже формирует выручку конкретного рынка.
--
-- Запрос содержит:
--   4 JOIN, GROUP BY, CASE, WHERE и оконную функцию RANK
-- ============================================================


-- ------------------------------------------------------------
-- Основной запрос
-- ------------------------------------------------------------

WITH customer_revenue AS (
		SELECT
			co.country,
			ci.city,
			c.customer_id,
			c.first_name || ' ' || c.last_name AS customer_name,
			COUNT(p.payment_id) AS payments_count,
			SUM(p.amount)       AS total_amount
		FROM customer AS c
		-- JOIN 1-3: от клиента добираемся до страны через адрес и город
		INNER JOIN address AS a  ON a.address_id  = c.address_id
		INNER JOIN city    AS ci ON ci.city_id    = a.city_id
		INNER JOIN country AS co ON co.country_id = ci.country_id
		-- JOIN 4: платежи клиента
		INNER JOIN payment AS p  ON p.customer_id = c.customer_id
		-- WHERE: нулевые платежи отбрасываем, это технические записи
		-- (возвраты и исправления), выручкой они не являются
		WHERE p.amount > 0
		GROUP BY
			co.country,
			ci.city,
			c.customer_id,
			c.first_name,
			c.last_name
	)

SELECT
	country,
	city,
	customer_name,
	payments_count,
	total_amount,
	-- Оконная функция: место клиента по выручке внутри своей страны.
	-- PARTITION BY перезапускает нумерацию на каждой новой стране.
	RANK() OVER (PARTITION BY country ORDER BY total_amount DESC) AS rank_in_country,
	-- CASE: сегмент клиента по сумме платежей
	CASE
		WHEN total_amount >= 150 THEN 'ключевой'
		WHEN total_amount >= 100 THEN 'постоянный'
		ELSE 'обычный'
	END AS segment
FROM customer_revenue
ORDER BY country, rank_in_country;


-- ------------------------------------------------------------
-- Проверка 1: распределение по сегментам
-- ------------------------------------------------------------
-- Границы сегментов выбраны не наугад: суммы на клиента лежат
-- в диапазоне от 27.93 до 211.55, медиана равна 99.74.
-- Проверим, что ни один сегмент не оказался пустым или
-- не поглотил всех остальных.

WITH customer_revenue AS (
		SELECT
			c.customer_id,
			SUM(p.amount) AS total_amount
		FROM customer AS c
		INNER JOIN payment AS p ON p.customer_id = c.customer_id
		WHERE p.amount > 0
		GROUP BY c.customer_id
	)

SELECT
	CASE
		WHEN total_amount >= 150 THEN 'ключевой'
		WHEN total_amount >= 100 THEN 'постоянный'
		ELSE 'обычный'
	END AS segment,
	COUNT(*) AS clients,
	CAST(MIN(total_amount) AS NUMERIC(8,2)) AS min_amount,
	CAST(MAX(total_amount) AS NUMERIC(8,2)) AS max_amount
FROM customer_revenue
GROUP BY segment
ORDER BY min_amount DESC;


-- ------------------------------------------------------------
-- Проверка 2: страны с наибольшей выручкой
-- ------------------------------------------------------------
-- Полезно посмотреть, где лидер рынка действительно выделяется,
-- а где выручка размазана между клиентами ровным слоем.

WITH customer_revenue AS (
		SELECT
			co.country,
			c.customer_id,
			SUM(p.amount) AS total_amount
		FROM customer AS c
		INNER JOIN address AS a  ON a.address_id  = c.address_id
		INNER JOIN city    AS ci ON ci.city_id    = a.city_id
		INNER JOIN country AS co ON co.country_id = ci.country_id
		INNER JOIN payment AS p  ON p.customer_id = c.customer_id
		WHERE p.amount > 0
		GROUP BY co.country, c.customer_id
	)

SELECT
	country,
	COUNT(*) AS clients,
	CAST(SUM(total_amount) AS NUMERIC(10,2)) AS country_total,
	CAST(MAX(total_amount) AS NUMERIC(8,2))  AS best_client,
	CAST(MAX(total_amount) * 100.0 / SUM(total_amount) AS NUMERIC(5,1)) AS best_client_share_pct
FROM customer_revenue
GROUP BY country
ORDER BY country_total DESC
LIMIT 10;


-- ============================================================
-- Часть, относящаяся к теме урока: индексация
-- ============================================================

-- Посмотрим план выполнения основного запроса.

EXPLAIN ANALYZE
WITH customer_revenue AS (
		SELECT
			co.country,
			c.customer_id,
			SUM(p.amount) AS total_amount
		FROM customer AS c
		INNER JOIN address AS a  ON a.address_id  = c.address_id
		INNER JOIN city    AS ci ON ci.city_id    = a.city_id
		INNER JOIN country AS co ON co.country_id = ci.country_id
		INNER JOIN payment AS p  ON p.customer_id = c.customer_id
		WHERE p.amount > 0
		GROUP BY co.country, c.customer_id
	)
SELECT
	country,
	total_amount,
	RANK() OVER (PARTITION BY country ORDER BY total_amount DESC) AS rank_in_country
FROM customer_revenue;

-- Все соединения в запросе идут по первичным и внешним ключам,
-- а под первичный ключ PostgreSQL создаёт индекс автоматически.
-- Поэтому добавлять индексы для JOIN здесь нечего — они уже есть.


-- Зато условие отбора по неиндексированному полю — другое дело.
-- Поле payment_date индексом не покрыто. Проверим на нём,
-- как индекс влияет на план, и заодно убедимся, что влияет
-- он далеко не всегда.

-- Берём два фильтра разной ширины:
--   узкий  — 6 часов, попадает 317 строк из 14596 (около 2%)
--   широкий — месяц,  попадает 6754 строки из 14596 (около 46%)


-- Шаг 1. Замеры без индекса.

-- Индекс создаётся ниже, на шаге 2, и остаётся в базе после
-- выполнения файла. Чтобы при повторном запуске первый замер
-- действительно был «без индекса», сначала удаляем его
-- и обновляем статистику.

DROP INDEX IF EXISTS idx_payment_payment_date;

ANALYZE payment;


EXPLAIN ANALYZE
SELECT COUNT(*), SUM(amount)
FROM payment
WHERE payment_date >= '2007-04-30 00:00:00'
  AND payment_date <  '2007-04-30 06:00:00';
-- Seq Scan, Execution Time около 1.27 мс

EXPLAIN ANALYZE
SELECT COUNT(*), SUM(amount)
FROM payment
WHERE payment_date >= '2007-04-01'
  AND payment_date <  '2007-05-01';
-- Seq Scan, Execution Time около 1.93 мс


-- Шаг 2. Создаём индекс и обновляем статистику,
-- чтобы планировщик о нём узнал.

CREATE INDEX IF NOT EXISTS idx_payment_payment_date
	ON payment (payment_date);

ANALYZE payment;


-- Шаг 3. Те же два запроса после создания индекса.

EXPLAIN ANALYZE
SELECT COUNT(*), SUM(amount)
FROM payment
WHERE payment_date >= '2007-04-30 00:00:00'
  AND payment_date <  '2007-04-30 06:00:00';
-- Bitmap Index Scan on idx_payment_payment_date
-- Execution Time около 0.46 мс — быстрее примерно втрое

EXPLAIN ANALYZE
SELECT COUNT(*), SUM(amount)
FROM payment
WHERE payment_date >= '2007-04-01'
  AND payment_date <  '2007-05-01';
-- По-прежнему Seq Scan, Execution Time около 1.89 мс.
-- Индекс создан, но планировщик им не воспользовался.


-- Замечание про цифры: абсолютные времена зависят от машины
-- и от прогрева кэша и от запуска к запуску немного плавают.
-- Устойчивы два признака, и именно они важны: тип сканирования
-- в плане и соотношение времён до и после создания индекса.


-- Вывод по индексации:
-- индекс ускоряет выборку только тогда, когда условие отсекает
-- небольшую долю таблицы. При выборке половины строк обращение
-- к индексу, а затем к самим строкам обходится дороже, чем
-- честное последовательное чтение, и планировщик по стоимости
-- сам выбирает Seq Scan. Поэтому «создать индекс на всякий
-- случай» — плохая стратегия: он не ускорит такие запросы,
-- но будет занимать место и замедлять вставку и обновление.


-- Убрать индекс, если он больше не нужен:
-- DROP INDEX idx_payment_payment_date;
