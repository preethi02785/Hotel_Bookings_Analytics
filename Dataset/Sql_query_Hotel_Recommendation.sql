-- We are creating a new database to hold the tables
CREATE DATABASE HOTEL_DB;

-- Create File Format
-- TYPE indicates what type of file you want snowflake to accept
--FIELD_OPTIONALLY_ENCLOSED_BY handles quotes around fields
--SKIP_HEADER is used to skip the header rows
--NULL_IF defines values that should be treated as NULL
CREATE OR REPLACE FILE FORMAT FF_CSV
    TYPE = 'CSV'
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    SKIP_HEADER = 1
    NULL_IF = ('NULL','null', '')


--Create Stage
--stage is a temporary storage area in Snowflake
--upload CSV files to stage and INTO tables.

CREATE OR REPLACE STAGE STG_HOTEL_BOOKINGS
    FILE_FORMAT = (FORMAT_NAME = FF_CSV);

-- Create Table BRONZE_HOTEL_BOOKING
--Since CSV stores everything as text initially assign string
CREATE TABLE BRONZE_HOTEL_BOOKING (
    booking_id STRING,
    hotel_id STRING,
    hotel_city STRING,
    customer_id STRING,
    customer_name STRING,
    customer_email STRING,
    check_in_date STRING,
    check_out_date STRING,
    room_type STRING,
    num_guests STRING,
    total_amount STRING,
    currency STRING,
    booking_status STRING    
);


--Loading data from stage area to BRonze table
--Here @ means it directs snowflake to look in a stage not table or schema
COPY INTO BRONZE_HOTEL_BOOKING
FROM @STG_HOTEL_BOOKINGS
FILE_FORMAT = (FORMAT_NAME = FF_CSV)
ON_ERROR = 'CONTINUE';


SELECT * 
FROM BRONZE_HOTEL_BOOKING LIMIT 50;



--Create Silver table and assign appropriate datatypes
CREATE TABLE SILVER_HOTEL_BOOKINGS (
    booking_id VARCHAR,
    hotel_id INTEGER,
    hotel_city Varchar,
    customer_id VARCHAR,
    customer_name VARCHAR,
    customer_email VARCHAR,
    check_in_date DATE,
    check_out_date DATE,
    room_type VARCHAR,
    num_guests INTEGER,
    total_amount FLOAT,
    currency VARCHAR,
    booking_status VARCHAR
);


--Data cleaning steps 
--Checking if there are any invalid formats for email
SELECT customer_email
FROM BRONZE_HOTEL_BOOKING
WHERE NOT (customer_email LIKE '%@%.%')
        OR customer_email IS NULL

--Checking if total_amount is negative 
--since we are comparing string to num we use TRY_TO_NUMBER
SELECT total_amount
FROM BRONZE_HOTEL_BOOKING
WHERE 
    TRY_TO_NUMBER(total_amount)<0 
    OR TRY_TO_NUMBER(total_amount) IS NULL;


SELECT check_in_date, check_out_date
FROM BRONZE_HOTEL_BOOKING
WHERE TRY_TO_DATE(check_out_date)<TRY_TO_DATE(check_in_date);

SELECT num_guests
FROM BRONZE_HOTEL_BOOKING
WHERE 
    TRY_TO_NUMBER(num_guests) IS NULL 
    OR TRY_TO_NUMBER(num_guests) < 0
    OR TRY_TO_DOUBLE(num_guests) % 1 != 0;

SELECT DISTINCT booking_status
FROM BRONZE_HOTEL_BOOKING;

--Insert cleaned data to Silver layer
INSERT INTO SILVER_HOTEL_BOOKINGS
SELECT 
    booking_id,
    hotel_id,
    INITCAP(TRIM(hotel_city)) AS hotel_city,
    customer_id,
    INITCAP(TRIM(customer_name)) AS customer_name,
    CASE
        WHEN customer_email LIKE '%@%.%' THEN LOWER(TRIM(customer_email))
        ELSE NULL
    END AS customer_email,
    TRY_TO_DATE(NULLIF(check_in_date,'')) AS check_in_date,
    TRY_TO_DATE(NULLIF(check_out_date,'')) AS check_out_date,
    INITCAP(TRIM(room_type)) AS room_type,
    COALESCE(TRY_TO_NUMBER(NULLIF(num_guests, '')), 0) AS num_guests,
    ABS(TRY_TO_NUMBER(total_amount)) AS total_amount,
    UPPER(TRIM(currency)) AS currency,
    CASE
        WHEN LOWER(booking_status) LIKE 'confirm%ed' THEN 'Confirmed'
        ELSE booking_status
    END AS booking_status
    FROM BRONZE_HOTEL_BOOKING
    WHERE
        TRY_TO_DATE(check_in_date) IS NOT NULL
        AND TRY_TO_DATE(check_out_date) IS NOT NULL
        AND TRY_TO_DATE(check_out_date) >= TRY_TO_DATE(check_in_date);

    

SELECT *
FROM SILVER_HOTEL_BOOKINGS LIMIT 50;


--Creating gold tables for making analysis from the outputs
--Here we make data tables fit for generating analytical insights

--CASE 1: Daily Booking Revenue

CREATE TABLE GOLD_AGG_DAILY_BOOKING AS
SELECT
    check_in_date AS date,
    COUNT(*) AS total_bookings,
    SUM(total_amount) AS total_revenue
FROM SILVER_HOTEL_BOOKINGS
GROUP BY check_in_date;


--CASE 2: Revenue Based on cities
CREATE TABLE GOLD_AGG_HOTEL_CITY_REVENUE AS
SELECT 
    hotel_city AS city,
    SUM(total_amount) AS city_total_revenue
FROM SILVER_HOTEL_BOOKINGS
GROUP BY hotel_city;


--CASE 3: Monthly revenue and Monthly booking
CREATE TABLE GOLD_AGG_MONTHLY_REVENUE_BOOKING AS
SELECT 
    DATE_TRUNC('month',check_in_date) AS booking_months,
    COUNT(*) AS monthly_bookings,
    SUM(total_amount) AS total_monthly_revenue
FROM SILVER_HOTEL_BOOKINGS
GROUP BY DATE_TRUNC('month',check_in_date);

--CASE 4: Bookings by status
CREATE TABLE GOLD_AGG_BOOKING_STATUS AS
SELECT 
    booking_status,
    COUNT(*) AS bookings_by_status,
    SUM(total_amount) AS revenue_by_booking_status
FROM SILVER_HOTEL_BOOKINGS
GROUP BY booking_status;


--CASE 5: Bookings by room types
CREATE TABLE GOLD_AGG_ROOM_TYPE AS
SELECT 
    room_type,
    COUNT(*) AS total_booking_by_room_type,
    SUM(total_amount) AS total_revenue_room_type
FROM SILVER_HOTEL_BOOKINGS
GROUP BY room_type;




