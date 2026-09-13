-- ============================================================
-- Домашнее задание. Урок 13
-- CTI / EAV / Data Vault
--
-- Предметная область: производство, учёт технологического
-- оборудования на предприятии.
--
-- Сущность: единица оборудования.
-- Два типа: насос и электродвигатель.
--
-- Общие атрибуты (есть у любой единицы оборудования):
--     инвентарный номер, наименование, изготовитель, цех,
--     дата ввода в эксплуатацию, наработка в часах, состояние
--
-- Атрибуты насоса:
--     производительность, напор, тип рабочего колеса,
--     тип уплотнения
--
-- Атрибуты электродвигателя:
--     мощность, номинальные обороты, напряжение,
--     класс изоляции
--
-- Ниже одна и та же предметная область спроектирована
-- четырьмя способами.
-- ============================================================


-- ------------------------------------------------------------
-- Удаление предыдущих версий таблиц
-- ------------------------------------------------------------
-- Нужно, чтобы файл можно было запускать повторно: без этого
-- второй запуск остановится на ошибке «отношение уже существует».
-- CASCADE снимает внешние ключи дочерних таблиц, поэтому порядок
-- перечисления значения не имеет.
--
-- Из-за этих команд файл стоит выполнять в отдельной базе,
-- созданной под задание, а не в рабочей.

DROP TABLE IF EXISTS equipment_sti              CASCADE;
DROP TABLE IF EXISTS equipment_cti              CASCADE;
DROP TABLE IF EXISTS equipment_cti_pump         CASCADE;
DROP TABLE IF EXISTS equipment_cti_motor        CASCADE;
DROP TABLE IF EXISTS equipment_concrete_pump    CASCADE;
DROP TABLE IF EXISTS equipment_concrete_motor   CASCADE;
DROP TABLE IF EXISTS equipment_eav              CASCADE;
DROP TABLE IF EXISTS equipment_eav_attribute    CASCADE;
DROP TABLE IF EXISTS equipment_eav_value        CASCADE;


-- ============================================================
-- 1. SINGLE TABLE INHERITANCE
-- ============================================================
-- Оба типа лежат в одной таблице. Тип записи определяет поле
-- equipment_type. Поля, относящиеся к конкретному типу,
-- у остальных записей остаются пустыми.

CREATE TABLE equipment_sti (
	equipment_id      SERIAL       PRIMARY KEY,
	equipment_type    VARCHAR(20)  NOT NULL
		CHECK (equipment_type IN ('pump', 'motor')),

	-- общие атрибуты
	inventory_no      VARCHAR(20)  NOT NULL UNIQUE,
	name              VARCHAR(100) NOT NULL,
	manufacturer      VARCHAR(80),
	workshop          VARCHAR(50)  NOT NULL,
	commissioned_at   DATE         NOT NULL,
	operating_hours   INTEGER      NOT NULL DEFAULT 0
		CHECK (operating_hours >= 0),
	status            VARCHAR(20)  NOT NULL DEFAULT 'in_service'
		CHECK (status IN ('in_service', 'repair', 'reserve', 'written_off')),

	-- атрибуты только для насоса
	flow_rate_m3h     NUMERIC(8,2) CHECK (flow_rate_m3h > 0),
	head_m            NUMERIC(6,2) CHECK (head_m > 0),
	impeller_type     VARCHAR(30),
	sealing_type      VARCHAR(30),

	-- атрибуты только для электродвигателя
	power_kw          NUMERIC(8,2) CHECK (power_kw > 0),
	rated_rpm         INTEGER      CHECK (rated_rpm > 0),
	voltage_v         INTEGER      CHECK (voltage_v > 0),
	insulation_class  VARCHAR(5)
);

-- Плюсы: одна таблица, никаких JOIN, общие поля добавляются легко.
-- Минусы: для насоса четыре поля двигателя всегда пустые и наоборот.
-- На уровне таблицы нельзя потребовать, чтобы у насоса был указан
-- напор: поле обязано допускать пустое значение ради двигателей.


-- ============================================================
-- 2. COMMON (CLASS) TABLE INHERITANCE
-- ============================================================
-- В задании этот подход назван Common Table Inheritance,
-- на лекции — Class Table Inheritance. Речь об одном и том же.
--
-- Общие атрибуты вынесены в родительскую таблицу,
-- на каждый тип заведена своя дочерняя таблица.
-- Дочерняя запись связана с родительской по общему
-- идентификатору, который одновременно является
-- и первичным, и внешним ключом.

CREATE TABLE equipment_cti (
	equipment_id      SERIAL       PRIMARY KEY,
	equipment_type    VARCHAR(20)  NOT NULL
		CHECK (equipment_type IN ('pump', 'motor')),
	inventory_no      VARCHAR(20)  NOT NULL UNIQUE,
	name              VARCHAR(100) NOT NULL,
	manufacturer      VARCHAR(80),
	workshop          VARCHAR(50)  NOT NULL,
	commissioned_at   DATE         NOT NULL,
	operating_hours   INTEGER      NOT NULL DEFAULT 0
		CHECK (operating_hours >= 0),
	status            VARCHAR(20)  NOT NULL DEFAULT 'in_service'
		CHECK (status IN ('in_service', 'repair', 'reserve', 'written_off'))
);

CREATE TABLE equipment_cti_pump (
	equipment_id      INTEGER      PRIMARY KEY
		REFERENCES equipment_cti (equipment_id) ON DELETE CASCADE,
	flow_rate_m3h     NUMERIC(8,2) NOT NULL CHECK (flow_rate_m3h > 0),
	head_m            NUMERIC(6,2) NOT NULL CHECK (head_m > 0),
	impeller_type     VARCHAR(30)  NOT NULL,
	sealing_type      VARCHAR(30)
);

CREATE TABLE equipment_cti_motor (
	equipment_id      INTEGER      PRIMARY KEY
		REFERENCES equipment_cti (equipment_id) ON DELETE CASCADE,
	power_kw          NUMERIC(8,2) NOT NULL CHECK (power_kw > 0),
	rated_rpm         INTEGER      NOT NULL CHECK (rated_rpm > 0),
	voltage_v         INTEGER      NOT NULL CHECK (voltage_v > 0),
	insulation_class  VARCHAR(5)   NOT NULL
);

-- Плюсы: пустых полей нет, и теперь можно потребовать NOT NULL
-- для напора насоса — в таблице насосов он обязателен всегда.
-- Минусы: чтобы получить полную карточку насоса, нужен JOIN,
-- а добавление единицы оборудования затрагивает две таблицы.


-- ============================================================
-- 3. CONCRETE TABLE INHERITANCE
-- ============================================================
-- Общей родительской таблицы нет. Каждый тип живёт в своей
-- полностью самостоятельной таблице, общие поля дублируются.

CREATE TABLE equipment_concrete_pump (
	pump_id           SERIAL       PRIMARY KEY,

	-- общие атрибуты, продублированы
	inventory_no      VARCHAR(20)  NOT NULL UNIQUE,
	name              VARCHAR(100) NOT NULL,
	manufacturer      VARCHAR(80),
	workshop          VARCHAR(50)  NOT NULL,
	commissioned_at   DATE         NOT NULL,
	operating_hours   INTEGER      NOT NULL DEFAULT 0
		CHECK (operating_hours >= 0),
	status            VARCHAR(20)  NOT NULL DEFAULT 'in_service'
		CHECK (status IN ('in_service', 'repair', 'reserve', 'written_off')),

	-- собственные атрибуты
	flow_rate_m3h     NUMERIC(8,2) NOT NULL CHECK (flow_rate_m3h > 0),
	head_m            NUMERIC(6,2) NOT NULL CHECK (head_m > 0),
	impeller_type     VARCHAR(30)  NOT NULL,
	sealing_type      VARCHAR(30)
);

CREATE TABLE equipment_concrete_motor (
	motor_id          SERIAL       PRIMARY KEY,

	-- те же общие атрибуты, продублированы ещё раз
	inventory_no      VARCHAR(20)  NOT NULL UNIQUE,
	name              VARCHAR(100) NOT NULL,
	manufacturer      VARCHAR(80),
	workshop          VARCHAR(50)  NOT NULL,
	commissioned_at   DATE         NOT NULL,
	operating_hours   INTEGER      NOT NULL DEFAULT 0
		CHECK (operating_hours >= 0),
	status            VARCHAR(20)  NOT NULL DEFAULT 'in_service'
		CHECK (status IN ('in_service', 'repair', 'reserve', 'written_off')),

	-- собственные атрибуты
	power_kw          NUMERIC(8,2) NOT NULL CHECK (power_kw > 0),
	rated_rpm         INTEGER      NOT NULL CHECK (rated_rpm > 0),
	voltage_v         INTEGER      NOT NULL CHECK (voltage_v > 0),
	insulation_class  VARCHAR(5)   NOT NULL
);

-- Плюсы: каждая таблица проста и самодостаточна, JOIN не нужны.
-- Минусы: общие поля продублированы, и добавление, например,
-- материально ответственного лица потребует правки обеих таблиц.
-- Отдельная неприятность — уникальность инвентарного номера
-- гарантируется только внутри своей таблицы: насос и двигатель
-- теоретически могут получить один и тот же номер, и база
-- этого не заметит.
-- Чтобы получить список всего оборудования цеха, нужен UNION:
--
--     SELECT inventory_no, name, workshop, 'pump' AS equipment_type
--     FROM equipment_concrete_pump
--     UNION ALL
--     SELECT inventory_no, name, workshop, 'motor'
--     FROM equipment_concrete_motor;


-- ============================================================
-- 4. ENTITY - ATTRIBUTE - VALUE
-- ============================================================
-- Общие и обязательные атрибуты остаются в обычной таблице,
-- а всё, что различается между типами и может меняться,
-- выносится в универсальную структуру из трёх таблиц.

-- Сущность: то, что есть у любой единицы оборудования
CREATE TABLE equipment_eav (
	equipment_id      SERIAL       PRIMARY KEY,
	equipment_type    VARCHAR(20)  NOT NULL
		CHECK (equipment_type IN ('pump', 'motor')),
	inventory_no      VARCHAR(20)  NOT NULL UNIQUE,
	name              VARCHAR(100) NOT NULL,
	manufacturer      VARCHAR(80),
	workshop          VARCHAR(50)  NOT NULL,
	commissioned_at   DATE         NOT NULL,
	operating_hours   INTEGER      NOT NULL DEFAULT 0
		CHECK (operating_hours >= 0),
	status            VARCHAR(20)  NOT NULL DEFAULT 'in_service'
		CHECK (status IN ('in_service', 'repair', 'reserve', 'written_off'))
);

-- Атрибут: справочник характеристик.
-- Заводится один раз, новые характеристики добавляются
-- строкой в эту таблицу, а не изменением схемы базы.
CREATE TABLE equipment_eav_attribute (
	attribute_id      SERIAL       PRIMARY KEY,
	attribute_code    VARCHAR(40)  NOT NULL UNIQUE,
	attribute_name    VARCHAR(100) NOT NULL,
	unit              VARCHAR(20),
	value_type        VARCHAR(10)  NOT NULL
		CHECK (value_type IN ('number', 'text', 'date', 'bool')),
	applies_to        VARCHAR(20)
		CHECK (applies_to IN ('pump', 'motor', 'any'))
);

-- Значение: характеристика конкретной единицы оборудования
CREATE TABLE equipment_eav_value (
	value_id          SERIAL       PRIMARY KEY,
	equipment_id      INTEGER      NOT NULL
		REFERENCES equipment_eav (equipment_id) ON DELETE CASCADE,
	attribute_id      INTEGER      NOT NULL
		REFERENCES equipment_eav_attribute (attribute_id),

	-- под каждый тип данных своя колонка, заполняется одна из них
	value_number      NUMERIC(14,4),
	value_text        VARCHAR(255),
	value_date        DATE,
	value_bool        BOOLEAN,

	CONSTRAINT uq_equipment_attribute UNIQUE (equipment_id, attribute_id)
);

-- Пример наполнения справочника атрибутов:
--     ('flow_rate', 'Производительность', 'м3/ч', 'number', 'pump')
--     ('head',      'Напор',              'м',    'number', 'pump')
--     ('power',     'Мощность',           'кВт',  'number', 'motor')
--     ('rated_rpm', 'Номинальные обороты','об/мин','number','motor')
--
-- Плюсы: технолог может завести новую характеристику
-- самостоятельно, не обращаясь к разработчику и не меняя схему.
-- Минусы: контроль типов приходится тянуть на себе через
-- value_type, запросы усложняются, а чтобы собрать карточку
-- оборудования в привычном табличном виде, значения нужно
-- разворачивать из строк в колонки.


-- ============================================================
-- Какой подход выбрать для этой предметной области
-- ============================================================
-- Типов оборудования на реальном предприятии не два, а десятки,
-- и набор их паспортных характеристик заранее известен
-- и меняется редко. Поэтому разумной выглядит комбинация:
--
--   Common Table Inheritance для паспортных характеристик —
--   структура известна, и хочется сохранить ограничения
--   целостности, то есть требовать напор у насоса
--   и мощность у двигателя;
--
--   EAV дополнительно для тех характеристик, которые служба
--   эксплуатации заводит сама по ходу работы и состав которых
--   заранее не определён.
--
-- Single Table Inheritance здесь не подходит: при десятках
-- типов таблица превратится в сотню колонок, почти всегда
-- пустых. Concrete Table Inheritance тоже неудобен: сводные
-- отчёты по всему оборудованию цеха потребуют UNION из
-- десятков таблиц, а любое общее поле придётся добавлять
-- во все из них сразу.


-- ============================================================
-- Тестовые данные и проверка работоспособности
-- ============================================================
-- Две единицы оборудования — насос и электродвигатель —
-- заводятся в каждую из четырёх моделей, чтобы одну и ту же
-- карточку можно было собрать всеми четырьмя способами
-- и сравнить, во что обходится каждый из них.


-- ------------------------------------------------------------
-- 1. Single Table Inheritance
-- ------------------------------------------------------------
INSERT INTO equipment_sti (
	equipment_type, inventory_no, name, manufacturer, workshop,
	commissioned_at, operating_hours,
	flow_rate_m3h, head_m, impeller_type, sealing_type,
	power_kw, rated_rpm, voltage_v, insulation_class
)
VALUES
	('pump', 'NS-0418', 'Насос центробежный К 100-65', 'Ливгидромаш', 'Цех 5',
		'2021-06-15', 18400,
		100.00, 65.00, 'закрытое', 'торцевое',
		NULL, NULL, NULL, NULL),
	('motor', 'DV-1207', 'Двигатель асинхронный АИР 132М4', 'Элдин', 'Цех 5',
		'2022-03-02', 11250,
		NULL, NULL, NULL, NULL,
		11.00, 1460, 380, 'F');

-- Здесь сразу виден главный недостаток подхода: у насоса пусты
-- четыре поля двигателя, у двигателя — четыре поля насоса.


-- ------------------------------------------------------------
-- 2. Common (Class) Table Inheritance
-- ------------------------------------------------------------
INSERT INTO equipment_cti (
	equipment_type, inventory_no, name, manufacturer, workshop,
	commissioned_at, operating_hours
)
VALUES
	('pump', 'NS-0418', 'Насос центробежный К 100-65', 'Ливгидромаш', 'Цех 5',
		'2021-06-15', 18400),
	('motor', 'DV-1207', 'Двигатель асинхронный АИР 132М4', 'Элдин', 'Цех 5',
		'2022-03-02', 11250);

-- Дочерние записи привязываются к родительским по инвентарному
-- номеру: идентификатор выдаёт последовательность, и заранее
-- его значение неизвестно.
INSERT INTO equipment_cti_pump (equipment_id, flow_rate_m3h, head_m, impeller_type, sealing_type)
SELECT
	equipment_id,
	100.00,
	65.00,
	'закрытое',
	'торцевое'
FROM equipment_cti
WHERE inventory_no = 'NS-0418';

INSERT INTO equipment_cti_motor (equipment_id, power_kw, rated_rpm, voltage_v, insulation_class)
SELECT
	equipment_id,
	11.00,
	1460,
	380,
	'F'
FROM equipment_cti
WHERE inventory_no = 'DV-1207';


-- ------------------------------------------------------------
-- 3. Concrete Table Inheritance
-- ------------------------------------------------------------
INSERT INTO equipment_concrete_pump (
	inventory_no, name, manufacturer, workshop, commissioned_at,
	operating_hours, flow_rate_m3h, head_m, impeller_type, sealing_type
)
VALUES
	('NS-0418', 'Насос центробежный К 100-65', 'Ливгидромаш', 'Цех 5',
		'2021-06-15', 18400, 100.00, 65.00, 'закрытое', 'торцевое');

INSERT INTO equipment_concrete_motor (
	inventory_no, name, manufacturer, workshop, commissioned_at,
	operating_hours, power_kw, rated_rpm, voltage_v, insulation_class
)
VALUES
	('DV-1207', 'Двигатель асинхронный АИР 132М4', 'Элдин', 'Цех 5',
		'2022-03-02', 11250, 11.00, 1460, 380, 'F');


-- ------------------------------------------------------------
-- 4. Entity - Attribute - Value
-- ------------------------------------------------------------
-- Сначала справочник характеристик, затем сами единицы
-- оборудования, затем значения.
INSERT INTO equipment_eav_attribute (attribute_code, attribute_name, unit, value_type, applies_to)
VALUES
	('flow_rate', 'Производительность',  'м3/ч',   'number', 'pump'),
	('head',      'Напор',               'м',      'number', 'pump'),
	('power',     'Мощность',            'кВт',    'number', 'motor'),
	('rated_rpm', 'Номинальные обороты', 'об/мин', 'number', 'motor');

INSERT INTO equipment_eav (
	equipment_type, inventory_no, name, manufacturer, workshop,
	commissioned_at, operating_hours
)
VALUES
	('pump', 'NS-0419', 'Насос центробежный К 45-30', 'Ливгидромаш', 'Цех 7',
		'2023-09-04', 6120),
	('motor', 'DV-1208', 'Двигатель асинхронный АИР 100L4', 'Элдин', 'Цех 7',
		'2023-09-04', 6120);

-- Значение ссылается и на оборудование, и на характеристику,
-- поэтому оба идентификатора берутся подзапросами по коду.
INSERT INTO equipment_eav_value (equipment_id, attribute_id, value_number)
VALUES
	(
		(SELECT equipment_id FROM equipment_eav WHERE inventory_no = 'NS-0419'),
		(SELECT attribute_id FROM equipment_eav_attribute WHERE attribute_code = 'flow_rate'),
		40.0000
	),
	(
		(SELECT equipment_id FROM equipment_eav WHERE inventory_no = 'NS-0419'),
		(SELECT attribute_id FROM equipment_eav_attribute WHERE attribute_code = 'head'),
		25.0000
	),
	(
		(SELECT equipment_id FROM equipment_eav WHERE inventory_no = 'DV-1208'),
		(SELECT attribute_id FROM equipment_eav_attribute WHERE attribute_code = 'power'),
		4.0000
	),
	(
		(SELECT equipment_id FROM equipment_eav WHERE inventory_no = 'DV-1208'),
		(SELECT attribute_id FROM equipment_eav_attribute WHERE attribute_code = 'rated_rpm'),
		1430.0000
	);


-- ------------------------------------------------------------
-- Проверка 1. Карточка насоса из Common Table Inheritance
-- ------------------------------------------------------------
-- Карточка собирается одним JOIN и приходит одной строкой
-- в привычном табличном виде.

SELECT
	e.inventory_no,
	e.name,
	e.workshop,
	p.flow_rate_m3h,
	p.head_m,
	p.sealing_type
FROM equipment_cti AS e
INNER JOIN equipment_cti_pump AS p
	ON p.equipment_id = e.equipment_id;


-- ------------------------------------------------------------
-- Проверка 2. Те же характеристики, но из EAV
-- ------------------------------------------------------------
-- Здесь каждая характеристика — отдельная строка, и чтобы
-- получить карточку привычного вида, значения пришлось бы
-- разворачивать из строк в колонки.

SELECT
	e.inventory_no,
	a.attribute_name,
	v.value_number,
	a.unit
FROM equipment_eav AS e
INNER JOIN equipment_eav_value AS v
	ON v.equipment_id = e.equipment_id
INNER JOIN equipment_eav_attribute AS a
	ON a.attribute_id = v.attribute_id
WHERE e.inventory_no = 'NS-0419'
ORDER BY a.attribute_name;


-- ------------------------------------------------------------
-- Проверка 3. Сводный список оборудования
-- ------------------------------------------------------------
-- Сравнение, во что обходится сводный отчёт в разных моделях.
-- В Single Table достаточно обычного SELECT, а в Concrete Table
-- нужен UNION ALL из двух таблиц — и это при двух типах
-- оборудования, тогда как на предприятии их десятки.

SELECT
	'Single Table' AS model,
	inventory_no,
	name,
	equipment_type
FROM equipment_sti

UNION ALL

SELECT
	'Concrete Table',
	inventory_no,
	name,
	'pump'
FROM equipment_concrete_pump

UNION ALL

SELECT
	'Concrete Table',
	inventory_no,
	name,
	'motor'
FROM equipment_concrete_motor

ORDER BY model, inventory_no;


-- ------------------------------------------------------------
-- Проверка 4. Сколько строк заняли одни и те же данные
-- ------------------------------------------------------------
-- Две единицы оборудования занимают разное число строк:
-- в Single Table — две, в Common Table — четыре (две
-- родительские и две дочерние), в EAV — шесть (две сущности
-- и четыре значения).

SELECT
	'equipment_sti' AS table_name,
	COUNT(*) AS rows_count
FROM equipment_sti

UNION ALL
SELECT 'equipment_cti',            COUNT(*) FROM equipment_cti
UNION ALL
SELECT 'equipment_cti_pump',       COUNT(*) FROM equipment_cti_pump
UNION ALL
SELECT 'equipment_cti_motor',      COUNT(*) FROM equipment_cti_motor
UNION ALL
SELECT 'equipment_concrete_pump',  COUNT(*) FROM equipment_concrete_pump
UNION ALL
SELECT 'equipment_concrete_motor', COUNT(*) FROM equipment_concrete_motor
UNION ALL
SELECT 'equipment_eav',            COUNT(*) FROM equipment_eav
UNION ALL
SELECT 'equipment_eav_attribute',  COUNT(*) FROM equipment_eav_attribute
UNION ALL
SELECT 'equipment_eav_value',      COUNT(*) FROM equipment_eav_value

ORDER BY table_name;
