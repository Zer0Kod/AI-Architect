-- ============================================================
-- Домашнее задание. Урок 14
-- OLAP. Схема «СНЕЖИНКА»
--
-- Предметная область и зерно таблицы фактов те же, что
-- и в схеме «звезда»: одна строка = итог работы одной единицы
-- оборудования по одному виду продукции за одну смену.
--
-- Отличие только в измерениях. Повторяющиеся текстовые
-- атрибуты вынесены в отдельные справочники, поэтому
-- измерения выстраиваются в уровни.
--
-- Состав:
--     1 таблица фактов
--     5 измерений первого уровня  (dim_date, dim_shift,
--         dim_equipment, dim_product, dim_workshop)
--     4 измерения второго уровня  (dim_equipment_type,
--         dim_manufacturer, dim_product_category, dim_plant)
--     2 измерения третьего уровня (dim_product_group,
--         dim_region)
-- ============================================================


-- ------------------------------------------------------------
-- Удаление предыдущих версий таблиц
-- ------------------------------------------------------------
-- Нужно по двум причинам: чтобы файл можно было запускать
-- повторно и чтобы он не конфликтовал со схемой «звезда».
-- Обе схемы описывают одну предметную область, поэтому имена
-- таблицы фактов и измерений верхнего уровня у них совпадают.
-- CASCADE снимает внешние ключи вышестоящих таблиц, поэтому
-- порядок перечисления значения не имеет.
--
-- Из-за этих команд файл стоит выполнять в отдельной базе,
-- созданной под задание, а не в рабочей.

DROP TABLE IF EXISTS fact_production       CASCADE;
DROP TABLE IF EXISTS dim_date              CASCADE;
DROP TABLE IF EXISTS dim_shift             CASCADE;
DROP TABLE IF EXISTS dim_equipment         CASCADE;
DROP TABLE IF EXISTS dim_product           CASCADE;
DROP TABLE IF EXISTS dim_workshop          CASCADE;
DROP TABLE IF EXISTS dim_equipment_type    CASCADE;
DROP TABLE IF EXISTS dim_manufacturer      CASCADE;
DROP TABLE IF EXISTS dim_product_category  CASCADE;
DROP TABLE IF EXISTS dim_plant             CASCADE;
DROP TABLE IF EXISTS dim_product_group     CASCADE;
DROP TABLE IF EXISTS dim_region            CASCADE;


-- ============================================================
-- ИЗМЕРЕНИЯ ТРЕТЬЕГО УРОВНЯ
-- ============================================================

CREATE TABLE dim_product_group (
	product_group_id SMALLINT     PRIMARY KEY,
	group_code       VARCHAR(20)  NOT NULL UNIQUE,
	group_name       VARCHAR(60)  NOT NULL
);

CREATE TABLE dim_region (
	region_id        SMALLINT     PRIMARY KEY,
	region_name      VARCHAR(60)  NOT NULL UNIQUE,
	federal_district VARCHAR(60),
	country          VARCHAR(60)  NOT NULL DEFAULT 'Россия'
);


-- ============================================================
-- ИЗМЕРЕНИЯ ВТОРОГО УРОВНЯ
-- ============================================================

CREATE TABLE dim_product_category (
	category_id      SMALLINT     PRIMARY KEY,
	category_code    VARCHAR(20)  NOT NULL UNIQUE,
	category_name    VARCHAR(60)  NOT NULL,
	-- ссылка на вышестоящую группу продукции
	product_group_id SMALLINT     NOT NULL
		REFERENCES dim_product_group (product_group_id)
);

CREATE TABLE dim_equipment_type (
	equipment_type_id SMALLINT    PRIMARY KEY,
	type_code         VARCHAR(20) NOT NULL UNIQUE,
	type_name         VARCHAR(60) NOT NULL,
	-- к какому классу относится: основное или вспомогательное
	equipment_class   VARCHAR(30) NOT NULL
		CHECK (equipment_class IN ('основное', 'вспомогательное'))
);

CREATE TABLE dim_manufacturer (
	manufacturer_id  SMALLINT     PRIMARY KEY,
	manufacturer_name VARCHAR(80) NOT NULL UNIQUE,
	country          VARCHAR(60),
	support_contract BOOLEAN      NOT NULL DEFAULT FALSE
);

CREATE TABLE dim_plant (
	plant_id         SMALLINT     PRIMARY KEY,
	plant_code       VARCHAR(15)  NOT NULL UNIQUE,
	plant_name       VARCHAR(80)  NOT NULL,
	city             VARCHAR(60)  NOT NULL,
	-- ссылка на вышестоящий регион
	region_id        SMALLINT     NOT NULL
		REFERENCES dim_region (region_id)
);


-- ============================================================
-- ИЗМЕРЕНИЯ ПЕРВОГО УРОВНЯ
-- ============================================================

CREATE TABLE dim_date (
	date_id          INTEGER      PRIMARY KEY,   -- ГГГГММДД
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

CREATE TABLE dim_shift (
	shift_id         SMALLINT     PRIMARY KEY,
	shift_code       VARCHAR(10)  NOT NULL UNIQUE,
	shift_name       VARCHAR(40)  NOT NULL,
	start_time       TIME         NOT NULL,
	end_time         TIME         NOT NULL,
	duration_hours   NUMERIC(4,2) NOT NULL CHECK (duration_hours > 0),
	is_night         BOOLEAN      NOT NULL DEFAULT FALSE
);

CREATE TABLE dim_equipment (
	equipment_id     INTEGER      PRIMARY KEY,
	inventory_no     VARCHAR(20)  NOT NULL UNIQUE,
	equipment_name   VARCHAR(100) NOT NULL,
	model            VARCHAR(60),
	commissioned_at  DATE,
	rated_capacity   NUMERIC(10,2) CHECK (rated_capacity > 0),
	-- вместо текстовых значений — ссылки на справочники
	equipment_type_id SMALLINT    NOT NULL
		REFERENCES dim_equipment_type (equipment_type_id),
	manufacturer_id  SMALLINT
		REFERENCES dim_manufacturer (manufacturer_id)
);

CREATE TABLE dim_product (
	product_id       INTEGER      PRIMARY KEY,
	sku              VARCHAR(30)  NOT NULL UNIQUE,
	product_name     VARCHAR(120) NOT NULL,
	unit             VARCHAR(15)  NOT NULL,
	weight_kg        NUMERIC(10,3) CHECK (weight_kg > 0),
	is_active        BOOLEAN      NOT NULL DEFAULT TRUE,
	-- вместо текста категории — ссылка на справочник
	category_id      SMALLINT     NOT NULL
		REFERENCES dim_product_category (category_id)
);

CREATE TABLE dim_workshop (
	workshop_id      INTEGER      PRIMARY KEY,
	workshop_code    VARCHAR(15)  NOT NULL UNIQUE,
	workshop_name    VARCHAR(80)  NOT NULL,
	-- вместо текста завода — ссылка на справочник
	plant_id         SMALLINT     NOT NULL
		REFERENCES dim_plant (plant_id)
);


-- ============================================================
-- ТАБЛИЦА ФАКТОВ
-- ============================================================
-- Сама таблица фактов не изменилась по сравнению со звездой.
-- Нормализация затронула только измерения.

CREATE TABLE fact_production (
	fact_id          BIGSERIAL    PRIMARY KEY,

	date_id          INTEGER      NOT NULL REFERENCES dim_date (date_id),
	shift_id         SMALLINT     NOT NULL REFERENCES dim_shift (shift_id),
	equipment_id     INTEGER      NOT NULL REFERENCES dim_equipment (equipment_id),
	product_id       INTEGER      NOT NULL REFERENCES dim_product (product_id),
	workshop_id      INTEGER      NOT NULL REFERENCES dim_workshop (workshop_id),

	output_qty       NUMERIC(14,3) NOT NULL CHECK (output_qty >= 0),
	good_qty         NUMERIC(14,3) NOT NULL CHECK (good_qty >= 0),
	defect_qty       NUMERIC(14,3) NOT NULL DEFAULT 0 CHECK (defect_qty >= 0),
	runtime_minutes  INTEGER       NOT NULL CHECK (runtime_minutes >= 0),
	downtime_minutes INTEGER       NOT NULL DEFAULT 0 CHECK (downtime_minutes >= 0),
	energy_kwh       NUMERIC(12,3) CHECK (energy_kwh >= 0),

	CONSTRAINT chk_qty_consistency CHECK (good_qty + defect_qty <= output_qty),
	CONSTRAINT uq_fact_grain UNIQUE (date_id, shift_id, equipment_id, product_id)
);

CREATE INDEX idx_fact_production_date      ON fact_production (date_id);
CREATE INDEX idx_fact_production_equipment ON fact_production (equipment_id);
CREATE INDEX idx_fact_production_product   ON fact_production (product_id);
CREATE INDEX idx_fact_production_workshop  ON fact_production (workshop_id);


-- ============================================================
-- Тестовые данные
-- ============================================================
-- Данные те же, что и в схеме «звезда», но разложены
-- по уровням: сначала верхние справочники, потом нижние,
-- иначе внешние ключи не на что будет сослаться.
-- Именно этот порядок и есть плата за нормализацию.

-- Третий уровень
INSERT INTO dim_product_group (product_group_id, group_code, group_name)
VALUES
	(1, 'AUTOCHEM', 'Автохимия');

INSERT INTO dim_region (region_id, region_name, federal_district)
VALUES
	(1, 'Ярославская область', 'Центральный'),
	(2, 'Рязанская область',   'Центральный');

-- Второй уровень
INSERT INTO dim_product_category (category_id, category_code, category_name, product_group_id)
VALUES
	(1, 'ANTIFREEZE', 'Антифризы', 1),
	(2, 'OIL',        'Масла',     1);

INSERT INTO dim_equipment_type (equipment_type_id, type_code, type_name, equipment_class)
VALUES
	(1, 'FILL', 'Линия розлива', 'основное'),
	(2, 'PACK', 'Линия фасовки', 'основное');

INSERT INTO dim_manufacturer (manufacturer_id, manufacturer_name, country, support_contract)
VALUES
	(1, 'Ливгидромаш', 'Россия', TRUE),
	(2, 'Ижмаш',       'Россия', FALSE);

INSERT INTO dim_plant (plant_id, plant_code, plant_name, city, region_id)
VALUES
	(1, 'ZAV-1', 'Завод №1', 'Ярославль', 1),
	(2, 'ZAV-2', 'Завод №2', 'Рязань',    2);

-- Первый уровень
INSERT INTO dim_date (
	date_id, full_date, year, quarter, month, month_name,
	week_of_year, day_of_month, day_of_week, is_weekend
)
VALUES
	(20260907, '2026-09-07', 2026, 3, 9, 'Сентябрь', 37, 7, 1, FALSE),
	(20260908, '2026-09-08', 2026, 3, 9, 'Сентябрь', 37, 8, 2, FALSE);

INSERT INTO dim_shift (shift_id, shift_code, shift_name, start_time, end_time, duration_hours, is_night)
VALUES
	(1, 'D', 'Дневная', '08:00', '20:00', 12.00, FALSE),
	(2, 'N', 'Ночная',  '20:00', '08:00', 12.00, TRUE);

INSERT INTO dim_equipment (
	equipment_id, inventory_no, equipment_name, model,
	commissioned_at, rated_capacity, equipment_type_id, manufacturer_id
)
VALUES
	(1, 'LN-0101', 'Линия розлива №1', 'ЛР-2000', '2021-04-12', 2000.00, 1, 1),
	(2, 'LN-0202', 'Линия фасовки №2', 'ЛФ-1200', '2022-08-30', 1200.00, 2, 2);

INSERT INTO dim_product (product_id, sku, product_name, unit, weight_kg, category_id)
VALUES
	(1, 'AK-1000', 'Антифриз G12 5 л',         'шт', 5.400, 1),
	(2, 'OM-0500', 'Масло моторное 5W-40 4 л', 'шт', 3.600, 2);

INSERT INTO dim_workshop (workshop_id, workshop_code, workshop_name, plant_id)
VALUES
	(1, 'CEH-ROZ', 'Цех розлива', 1),
	(2, 'CEH-FAS', 'Цех фасовки', 2);

-- Факты — ровно те же строки, что и в звезде
INSERT INTO fact_production (
	date_id, shift_id, equipment_id, product_id, workshop_id,
	output_qty, good_qty, defect_qty, runtime_minutes, downtime_minutes, energy_kwh
)
VALUES
	(20260907, 1, 1, 1, 1, 1200.000, 1170.000, 30.000, 690,  30, 412.500),
	(20260907, 2, 1, 1, 1, 1100.000, 1060.000, 40.000, 660,  60, 398.200),
	(20260908, 1, 1, 1, 1, 1250.000, 1220.000, 30.000, 705,  15, 421.700),
	(20260908, 2, 1, 1, 1,  950.000,  910.000, 40.000, 600, 120, 361.400),

	(20260907, 1, 2, 2, 2,  700.000,  695.000,  5.000, 700,  20, 244.100),
	(20260907, 2, 2, 2, 2,  600.000,  595.000,  5.000, 650,  70, 231.800),
	(20260908, 1, 2, 2, 2,  650.000,  645.000,  5.000, 680,  40, 238.900),
	(20260908, 2, 2, 2, 2,  550.000,  545.000,  5.000, 620, 100, 225.300);


-- ============================================================
-- Аналитический запрос к снежинке
-- ============================================================
-- Тот же вопрос про долю брака, но с разрезом до региона
-- и до группы продукции. Здесь и видна цена нормализации:
-- до региона три соединения (цех, завод, регион) и ещё три
-- до группы продукции (продукция, категория, группа) —
-- шесть JOIN вместо двух, которые потребовались в звезде.

SELECT
	r.region_name,
	pl.plant_name,
	g.group_name,
	SUM(f.output_qty) AS output_total,
	SUM(f.defect_qty) AS defect_total,
	CAST(SUM(f.defect_qty) * 100.0 / SUM(f.output_qty) AS NUMERIC(5,2)) AS defect_pct
FROM fact_production AS f
INNER JOIN dim_workshop         AS w  ON w.workshop_id       = f.workshop_id
INNER JOIN dim_plant            AS pl ON pl.plant_id         = w.plant_id
INNER JOIN dim_region           AS r  ON r.region_id         = pl.region_id
INNER JOIN dim_product          AS p  ON p.product_id        = f.product_id
INNER JOIN dim_product_category AS c  ON c.category_id       = p.category_id
INNER JOIN dim_product_group    AS g  ON g.product_group_id  = c.product_group_id
WHERE f.output_qty > 0
GROUP BY r.region_name, pl.plant_name, g.group_name
ORDER BY defect_pct DESC;

-- Результат:
--  region_name         | plant_name | group_name | output_total | defect_total | defect_pct
-- ---------------------+------------+------------+--------------+--------------+------------
--  Ярославская область | Завод №1   | Автохимия  |     4500.000 |      140.000 |       3.11
--  Рязанская область   | Завод №2   | Автохимия  |     2500.000 |       20.000 |       0.80
--
-- Числа совпали с результатом звезды, как и должно быть:
-- данные одни и те же, различается только способ их хранения.


-- ------------------------------------------------------------
-- Во что обходится нормализация
-- ------------------------------------------------------------
-- Название завода в снежинке хранится в одной строке dim_plant,
-- а в звезде оно продублировано в каждой строке dim_workshop.
-- Посмотрим, сколько строк пришлось бы править при
-- переименовании завода.

SELECT
	pl.plant_name,
	COUNT(*) AS workshop_rows
FROM dim_workshop AS w
INNER JOIN dim_plant AS pl
	ON pl.plant_id = w.plant_id
GROUP BY pl.plant_name
ORDER BY pl.plant_name;
