-- ============================================================
-- Домашнее задание. Урок 14
-- OLAP. Схема «ЗВЕЗДА»
--
-- Предметная область: производство.
-- Аналитическая витрина выпуска продукции.
--
-- Зерно таблицы фактов (grain):
--     одна строка = итог работы одной единицы оборудования
--     по одному виду продукции за одну смену одного дня.
--
-- Состав: 1 таблица фактов и 5 таблиц измерений.
-- В схеме «звезда» измерения намеренно денормализованы:
-- тип оборудования, изготовитель, категория продукции и завод
-- хранятся текстом прямо в таблице измерения, без вынесения
-- в отдельные справочники. Это даёт ровно один JOIN от факта
-- до любого атрибута.
-- ============================================================


-- ------------------------------------------------------------
-- Удаление предыдущих версий таблиц
-- ------------------------------------------------------------
-- Нужно по двум причинам: чтобы файл можно было запускать
-- повторно и чтобы он не конфликтовал со схемой «снежинка».
-- Обе схемы описывают одну предметную область, поэтому имена
-- таблицы фактов и измерений верхнего уровня у них совпадают.
-- CASCADE снимает внешние ключи из таблицы фактов, поэтому
-- порядок перечисления значения не имеет.
--
-- Из-за этих команд файл стоит выполнять в отдельной базе,
-- созданной под задание, а не в рабочей.

DROP TABLE IF EXISTS fact_production CASCADE;
DROP TABLE IF EXISTS dim_date        CASCADE;
DROP TABLE IF EXISTS dim_shift       CASCADE;
DROP TABLE IF EXISTS dim_equipment   CASCADE;
DROP TABLE IF EXISTS dim_product     CASCADE;
DROP TABLE IF EXISTS dim_workshop    CASCADE;


-- ------------------------------------------------------------
-- ИЗМЕРЕНИЕ 1. Календарь
-- ------------------------------------------------------------
CREATE TABLE dim_date (
	date_id          INTEGER      PRIMARY KEY,   -- в формате ГГГГММДД, например 20260913
	full_date        DATE         NOT NULL UNIQUE,
	year             SMALLINT     NOT NULL,
	quarter          SMALLINT     NOT NULL CHECK (quarter BETWEEN 1 AND 4),
	month            SMALLINT     NOT NULL CHECK (month BETWEEN 1 AND 12),
	month_name       VARCHAR(20)  NOT NULL,
	week_of_year     SMALLINT     NOT NULL CHECK (week_of_year BETWEEN 1 AND 53),
	day_of_month     SMALLINT     NOT NULL CHECK (day_of_month BETWEEN 1 AND 31),
	day_of_week      SMALLINT     NOT NULL CHECK (day_of_week BETWEEN 1 AND 7),
	is_weekend       BOOLEAN      NOT NULL DEFAULT FALSE,
	is_holiday       BOOLEAN      NOT NULL DEFAULT FALSE
);


-- ------------------------------------------------------------
-- ИЗМЕРЕНИЕ 2. Смена
-- ------------------------------------------------------------
CREATE TABLE dim_shift (
	shift_id         SMALLINT     PRIMARY KEY,
	shift_code       VARCHAR(10)  NOT NULL UNIQUE,
	shift_name       VARCHAR(40)  NOT NULL,
	start_time       TIME         NOT NULL,
	end_time         TIME         NOT NULL,
	duration_hours   NUMERIC(4,2) NOT NULL CHECK (duration_hours > 0),
	is_night         BOOLEAN      NOT NULL DEFAULT FALSE
);


-- ------------------------------------------------------------
-- ИЗМЕРЕНИЕ 3. Оборудование (денормализовано)
-- ------------------------------------------------------------
CREATE TABLE dim_equipment (
	equipment_id     INTEGER      PRIMARY KEY,
	inventory_no     VARCHAR(20)  NOT NULL UNIQUE,
	equipment_name   VARCHAR(100) NOT NULL,
	-- тип и изготовитель лежат текстом прямо здесь
	equipment_type   VARCHAR(50)  NOT NULL,
	manufacturer     VARCHAR(80),
	manufacturer_country VARCHAR(60),
	model            VARCHAR(60),
	commissioned_at  DATE,
	rated_capacity   NUMERIC(10,2)                -- паспортная производительность, ед/ч
		CHECK (rated_capacity > 0)
);


-- ------------------------------------------------------------
-- ИЗМЕРЕНИЕ 4. Продукция (денормализовано)
-- ------------------------------------------------------------
CREATE TABLE dim_product (
	product_id       INTEGER      PRIMARY KEY,
	sku              VARCHAR(30)  NOT NULL UNIQUE,
	product_name     VARCHAR(120) NOT NULL,
	-- категория и группа лежат текстом прямо здесь
	category_name    VARCHAR(60)  NOT NULL,
	product_group    VARCHAR(60)  NOT NULL,
	unit             VARCHAR(15)  NOT NULL,
	weight_kg        NUMERIC(10,3) CHECK (weight_kg > 0),
	is_active        BOOLEAN      NOT NULL DEFAULT TRUE
);


-- ------------------------------------------------------------
-- ИЗМЕРЕНИЕ 5. Подразделение (денормализовано)
-- ------------------------------------------------------------
CREATE TABLE dim_workshop (
	workshop_id      INTEGER      PRIMARY KEY,
	workshop_code    VARCHAR(15)  NOT NULL UNIQUE,
	workshop_name    VARCHAR(80)  NOT NULL,
	-- завод и его расположение лежат текстом прямо здесь
	plant_name       VARCHAR(80)  NOT NULL,
	plant_city       VARCHAR(60)  NOT NULL,
	plant_region     VARCHAR(60)
);


-- ------------------------------------------------------------
-- ТАБЛИЦА ФАКТОВ
-- ------------------------------------------------------------
CREATE TABLE fact_production (
	fact_id          BIGSERIAL    PRIMARY KEY,

	-- внешние ключи на измерения
	date_id          INTEGER      NOT NULL REFERENCES dim_date (date_id),
	shift_id         SMALLINT     NOT NULL REFERENCES dim_shift (shift_id),
	equipment_id     INTEGER      NOT NULL REFERENCES dim_equipment (equipment_id),
	product_id       INTEGER      NOT NULL REFERENCES dim_product (product_id),
	workshop_id      INTEGER      NOT NULL REFERENCES dim_workshop (workshop_id),

	-- меры
	output_qty       NUMERIC(14,3) NOT NULL CHECK (output_qty >= 0),
	good_qty         NUMERIC(14,3) NOT NULL CHECK (good_qty >= 0),
	defect_qty       NUMERIC(14,3) NOT NULL DEFAULT 0 CHECK (defect_qty >= 0),
	runtime_minutes  INTEGER       NOT NULL CHECK (runtime_minutes >= 0),
	downtime_minutes INTEGER       NOT NULL DEFAULT 0 CHECK (downtime_minutes >= 0),
	energy_kwh       NUMERIC(12,3) CHECK (energy_kwh >= 0),

	-- годное и брак в сумме не могут превышать выпуск
	CONSTRAINT chk_qty_consistency CHECK (good_qty + defect_qty <= output_qty),

	-- зерно витрины: один факт на сочетание
	-- дата, смена, оборудование, продукция
	CONSTRAINT uq_fact_grain UNIQUE (date_id, shift_id, equipment_id, product_id)
);


-- ------------------------------------------------------------
-- Индексы под типовые аналитические запросы
-- ------------------------------------------------------------
CREATE INDEX idx_fact_production_date      ON fact_production (date_id);
CREATE INDEX idx_fact_production_equipment ON fact_production (equipment_id);
CREATE INDEX idx_fact_production_product   ON fact_production (product_id);
CREATE INDEX idx_fact_production_workshop  ON fact_production (workshop_id);


-- ============================================================
-- Тестовые данные
-- ============================================================
-- Небольшой набор, которого хватает, чтобы аналитический запрос
-- вернул осмысленный результат: два цеха на двух заводах,
-- два вида продукции, две единицы оборудования, два дня
-- по две смены.

INSERT INTO dim_date (
	date_id, full_date, year, quarter, month, month_name,
	week_of_year, day_of_month, day_of_week, is_weekend
)
VALUES
	(20260907, '2026-09-07', 2026, 3, 9, 'Сентябрь', 37,  7, 1, FALSE),
	(20260908, '2026-09-08', 2026, 3, 9, 'Сентябрь', 37,  8, 2, FALSE);

INSERT INTO dim_shift (shift_id, shift_code, shift_name, start_time, end_time, duration_hours, is_night)
VALUES
	(1, 'D', 'Дневная', '08:00', '20:00', 12.00, FALSE),
	(2, 'N', 'Ночная',  '20:00', '08:00', 12.00, TRUE);

INSERT INTO dim_equipment (
	equipment_id, inventory_no, equipment_name, equipment_type,
	manufacturer, manufacturer_country, model, commissioned_at, rated_capacity
)
VALUES
	(1, 'LN-0101', 'Линия розлива №1',  'Линия розлива',
		'Ливгидромаш', 'Россия', 'ЛР-2000', '2021-04-12', 2000.00),
	(2, 'LN-0202', 'Линия фасовки №2',  'Линия фасовки',
		'Ижмаш', 'Россия', 'ЛФ-1200', '2022-08-30', 1200.00);

INSERT INTO dim_product (
	product_id, sku, product_name, category_name, product_group, unit, weight_kg
)
VALUES
	(1, 'AK-1000', 'Антифриз G12 5 л',        'Антифризы',   'Автохимия', 'шт', 5.400),
	(2, 'OM-0500', 'Масло моторное 5W-40 4 л', 'Масла',      'Автохимия', 'шт', 3.600);

INSERT INTO dim_workshop (
	workshop_id, workshop_code, workshop_name, plant_name, plant_city, plant_region
)
VALUES
	(1, 'CEH-ROZ', 'Цех розлива',  'Завод №1', 'Ярославль', 'Ярославская область'),
	(2, 'CEH-FAS', 'Цех фасовки',  'Завод №2', 'Рязань',    'Рязанская область');

INSERT INTO fact_production (
	date_id, shift_id, equipment_id, product_id, workshop_id,
	output_qty, good_qty, defect_qty, runtime_minutes, downtime_minutes, energy_kwh
)
VALUES
	-- цех розлива, линия розлива, антифриз
	(20260907, 1, 1, 1, 1, 1200.000, 1170.000, 30.000, 690,  30, 412.500),
	(20260907, 2, 1, 1, 1, 1100.000, 1060.000, 40.000, 660,  60, 398.200),
	(20260908, 1, 1, 1, 1, 1250.000, 1220.000, 30.000, 705,  15, 421.700),
	(20260908, 2, 1, 1, 1,  950.000,  910.000, 40.000, 600, 120, 361.400),

	-- цех фасовки, линия фасовки, моторное масло
	(20260907, 1, 2, 2, 2,  700.000,  695.000,  5.000, 700,  20, 244.100),
	(20260907, 2, 2, 2, 2,  600.000,  595.000,  5.000, 650,  70, 231.800),
	(20260908, 1, 2, 2, 2,  650.000,  645.000,  5.000, 680,  40, 238.900),
	(20260908, 2, 2, 2, 2,  550.000,  545.000,  5.000, 620, 100, 225.300);


-- ============================================================
-- Аналитический запрос к звезде
-- ============================================================
-- Доля брака по цехам и месяцам.
-- От факта до любого атрибута ровно один JOIN.
--
-- Процент брака считается на лету, а не хранится в факте:
-- проценты между сменами складывать нельзя, а выпуск и брак —
-- можно, поэтому в таблице лежат именно они.

SELECT
	d.year,
	d.month_name,
	w.workshop_name,
	SUM(f.output_qty) AS output_total,
	SUM(f.defect_qty) AS defect_total,
	CAST(SUM(f.defect_qty) * 100.0 / SUM(f.output_qty) AS NUMERIC(5,2)) AS defect_pct
FROM fact_production AS f
INNER JOIN dim_date     AS d ON d.date_id     = f.date_id
INNER JOIN dim_workshop AS w ON w.workshop_id = f.workshop_id
WHERE f.output_qty > 0
GROUP BY d.year, d.month_name, w.workshop_name
ORDER BY defect_pct DESC;

-- Результат:
--  year | month_name | workshop_name | output_total | defect_total | defect_pct
-- ------+------------+---------------+--------------+--------------+------------
--  2026 | Сентябрь   | Цех розлива   |     4500.000 |      140.000 |       3.11
--  2026 | Сентябрь   | Цех фасовки   |     2500.000 |       20.000 |       0.80


-- ------------------------------------------------------------
-- Проверка зерна
-- ------------------------------------------------------------
-- Зерно объявлено как «дата, смена, оборудование, продукция».
-- Убедимся, что строк ровно столько же, сколько уникальных
-- сочетаний этих четырёх ключей: если числа разошлись бы,
-- значит ограничение уникальности не соблюдается и меры
-- при суммировании задваивались бы.

SELECT
	COUNT(*) AS fact_rows,
	COUNT(DISTINCT (date_id, shift_id, equipment_id, product_id)) AS distinct_grain
FROM fact_production;
