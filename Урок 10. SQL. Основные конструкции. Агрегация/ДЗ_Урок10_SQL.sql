-- ============================================================
-- Домашнее задание. Урок 10
-- Язык запросов SQL. Основные конструкции. Агрегация
-- Учебная база: dvdrental (PostgreSQL)
-- ============================================================


-- ------------------------------------------------------------
-- Задание 1. Установка учебной БД dvdrental
-- ------------------------------------------------------------
-- База развёрнута из архива dvdrental.tar.
-- Проверка, что данные на месте:

SELECT
	COUNT(*)                    AS payments_total,
	COUNT(DISTINCT customer_id) AS customers_total
FROM payment;


-- ------------------------------------------------------------
-- Задание 2. Клиенты по убыванию количества платежей
-- ------------------------------------------------------------
-- Группируем платежи по клиенту и считаем, сколько строк
-- (то есть платежей) приходится на каждого.

SELECT
	customer_id,
	COUNT(payment_id) AS payments_count
FROM payment
GROUP BY customer_id
ORDER BY payments_count DESC;


-- ------------------------------------------------------------
-- Задание 3. Признак frequent_payer
-- ------------------------------------------------------------
-- Признак равен 1, если платежей больше 30, иначе 0.
-- CASE вычисляется уже после группировки, поэтому внутри него
-- пишется та же агрегатная функция COUNT(payment_id),
-- а не имя алиаса payments_count: алиас из SELECT в этот
-- момент ещё не определён.

SELECT
	customer_id,
	COUNT(payment_id) AS payments_count,
	CASE
		WHEN COUNT(payment_id) > 30 THEN 1
		ELSE 0
	END AS frequent_payer
FROM payment
GROUP BY customer_id
ORDER BY payments_count DESC;


-- Сколько всего клиентов получили признак frequent_payer = 1.
-- Здесь условие по группе, поэтому используется HAVING, а не WHERE.

SELECT COUNT(*) AS frequent_payers_count
FROM (
		SELECT customer_id
		FROM payment
		GROUP BY customer_id
		HAVING COUNT(payment_id) > 30
	) AS frequent;


-- ------------------------------------------------------------
-- Задание 4. Клиенты по убыванию суммы платежей
-- ------------------------------------------------------------

SELECT
	customer_id,
	SUM(amount) AS total_amount
FROM payment
GROUP BY customer_id
ORDER BY total_amount DESC;


-- ------------------------------------------------------------
-- Задание 5. Признак prospective_client
-- ------------------------------------------------------------
-- Признак равен 1, если сумма платежей клиента выше медианы.
-- Медиану считаем отдельно, как и требует задание.

-- Шаг 5.1. Сколько всего клиентов в таблице платежей.
-- Это нужно, чтобы понять, какое значение является серединой.

SELECT COUNT(DISTINCT customer_id) AS customers_count
FROM payment;

-- Результат: 599 клиентов.
-- Число нечётное, значит медиана — это ровно одно значение,
-- стоящее посередине упорядоченного ряда, а именно 300-е.
-- Слева и справа от него остаётся по 299 значений.


-- Шаг 5.2. Находим само медианное значение.
-- Сортируем суммы по возрастанию, пропускаем первые 299 строк
-- и берём следующую — она и будет серединой ряда.

SELECT total_amount AS median_amount
FROM (
		SELECT SUM(amount) AS total_amount
		FROM payment
		GROUP BY customer_id
		ORDER BY total_amount
	) AS totals
LIMIT 1 OFFSET 299;

-- Результат: медиана равна 99.74


-- Шаг 5.3. Проставляем признак prospective_client.
-- Медиана подставлена найденным на шаге 5.2 числом.

SELECT
	customer_id,
	SUM(amount) AS total_amount,
	CASE
		WHEN SUM(amount) > 99.74 THEN 1
		ELSE 0
	END AS prospective_client
FROM payment
GROUP BY customer_id
ORDER BY total_amount DESC;


-- Тот же запрос, но медиана не вписана числом, а считается
-- подзапросом. Такой вариант не придётся править вручную,
-- если данные в таблице изменятся.

SELECT
	customer_id,
	SUM(amount) AS total_amount,
	CASE
		WHEN SUM(amount) > (
				SELECT total_amount
				FROM (
						SELECT SUM(amount) AS total_amount
						FROM payment
						GROUP BY customer_id
						ORDER BY total_amount
					) AS totals
				LIMIT 1 OFFSET 299
			) THEN 1
		ELSE 0
	END AS prospective_client
FROM payment
GROUP BY customer_id
ORDER BY total_amount DESC;


-- ------------------------------------------------------------
-- Проверка результата
-- ------------------------------------------------------------
-- Признак построен относительно медианы, поэтому клиентов
-- с prospective_client = 1 должно быть примерно половина.

SELECT
	prospective_client,
	COUNT(*) AS clients
FROM (
		SELECT
			customer_id,
			CASE
				WHEN SUM(amount) > 99.74 THEN 1
				ELSE 0
			END AS prospective_client
		FROM payment
		GROUP BY customer_id
	) AS marked
GROUP BY prospective_client
ORDER BY prospective_client DESC;

-- Получилось 298 единиц против 301 нуля. Ровно пополам не вышло,
-- и причину видно, если разложить клиентов на три группы.
-- SUM от CASE позволяет получить сразу несколько счётчиков
-- за один проход по данным.

SELECT
	COUNT(*) AS clients_total,
	SUM(CASE WHEN total_amount > 99.74 THEN 1 ELSE 0 END) AS above_median,
	SUM(CASE WHEN total_amount = 99.74 THEN 1 ELSE 0 END) AS equal_median,
	SUM(CASE WHEN total_amount < 99.74 THEN 1 ELSE 0 END) AS below_median
FROM (
		SELECT SUM(amount) AS total_amount
		FROM payment
		GROUP BY customer_id
	) AS totals;

-- Результат: 298 выше медианы, 2 ровно на медиане, 299 ниже.
-- Медианное значение оказалось не уникальным: сумму 99.74
-- набрали два клиента. Условие в CASE строгое, поэтому оба
-- попали в нулевую группу, отсюда 301 = 299 + 2.
