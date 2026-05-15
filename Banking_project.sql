CREATE DATABASE BANKING_DB;
USE DATABASE BANKING_DB;

CREATE WAREHOUSE BANKING_WH
WITH
WAREHOUSE_SIZE='XSMALL'
AUTO_SUSPEND=60
AUTO_RESUME=TRUE;

CREATE RESOURCE MONITOR BANK_MONITOR
WITH CREDIT_QUOTA = 50
TRIGGERS
ON 80 PERCENT DO NOTIFY
ON 100 PERCENT DO SUSPEND;

CREATE SCHEMA BANKING_SCHEMA;
USE SCHEMA BANKING_SCHEMA;

CREATE STAGE BANK_STAGE;

LIST @BANK_STAGE;

CREATE FILE FORMAT CSV_FORMAT
TYPE = CSV
SKIP_HEADER = 1
FIELD_OPTIONALLY_ENCLOSED_BY = '"';

CREATE TABLE CUSTOMER_RAW (
CUSTOMER_ID STRING,
CUSTOMER_NAME STRING,
EMAIL STRING,
CITY STRING,
ACCOUNT_TYPE STRING
);

CREATE TABLE ACCOUNT_RAW (
ACCOUNT_ID STRING,
CUSTOMER_ID STRING,
BALANCE NUMBER,
ACCOUNT_STATUS STRING
);

CREATE TABLE TRANSACTION_RAW (
TRANSACTION_ID STRING,
ACCOUNT_ID STRING,
TRANSACTION_AMOUNT NUMBER,
TRANSACTION_TYPE STRING,
TRANSACTION_DATE DATE
);

CREATE TABLE LOAN_RAW (
LOAN_ID STRING,
CUSTOMER_ID STRING,
LOAN_AMOUNT NUMBER,
INTEREST_RATE NUMBER,
LOAN_STATUS STRING
);

CREATE TABLE FRAUD_ALERT_RAW (
ALERT_ID STRING,
TRANSACTION_ID STRING,
FRAUD_SCORE NUMBER,
REASON STRING,
STATUS STRING
);

COPY INTO CUSTOMER_RAW
FROM @BANK_STAGE/customers_400.csv
FILE_FORMAT = CSV_FORMAT;

//create table acc to files
DROP TABLE CUSTOMER_RAW;
CREATE OR REPLACE TABLE CUSTOMER_RAW (
    CUSTOMER_ID STRING,
    NAME STRING,
    CITY STRING,
    PHONE STRING,
    EMAIL STRING,
    JOIN_DATE DATE
);

COPY INTO CUSTOMER_RAW
FROM @BANK_STAGE/customers_400.csv
FILE_FORMAT = CSV_FORMAT;

select *from customer_raw;

DROP TABLE ACCOUNT_RAW;
CREATE OR REPLACE TABLE ACCOUNT_RAW (
    ACCOUNT_ID STRING,
    CUSTOMER_ID STRING,
    ACCOUNT_TYPE STRING,
    BALANCE NUMBER,
    OPEN_DATE DATE
);

COPY INTO ACCOUNT_RAW
FROM @BANK_STAGE/accounts_400.csv
FILE_FORMAT = (
TYPE = CSV
SKIP_HEADER = 1
FIELD_OPTIONALLY_ENCLOSED_BY='"'
);
select *from account_raw;

DROP TABLE TRANSACTION_RAW;

CREATE OR REPLACE TABLE TRANSACTION_RAW (
    TRANSACTION_ID STRING,
    ACCOUNT_ID STRING,
    TRANSACTION_TYPE STRING,
    AMOUNT NUMBER,
    TRANSACTION_DATE DATE,
    TRANSACTION_TIME STRING,
    LOCATION STRING,
    FRAUD_FLAG STRING
);

COPY INTO TRANSACTION_RAW
FROM @BANK_STAGE/transactions_400.csv
FILE_FORMAT = (
TYPE = CSV
SKIP_HEADER = 1
FIELD_OPTIONALLY_ENCLOSED_BY='"'BANKING_DB.BANKING_SCHEMA.BANK_STAGE
);
select *from transaction_raw;

DROP TABLE FRAUD_ALERT_RAW;

CREATE OR REPLACE TABLE FRAUD_ALERT_RAW (
    TRANSACTION_ID STRING,
    ACCOUNT_ID STRING,
    TRANSACTION_TYPE STRING,
    AMOUNT NUMBER,
    TRANSACTION_DATE DATE,
    TRANSACTION_TIME STRING,
    LOCATION STRING,
    FRAUD_FLAG STRING,
    ALERT_ID STRING,
    RISK_LEVEL STRING
);

COPY INTO FRAUD_ALERT_RAW
FROM @BANK_STAGE/fraud_alerts_400.csv
FILE_FORMAT = (
TYPE = CSV
SKIP_HEADER = 1
FIELD_OPTIONALLY_ENCLOSED_BY='"'
);

select*from fraud_Alert_raw;

create or replace table  dim_customer_raw as 
select distinct customer_id,name,city,phone,email from customer_raw;

create or replace table dim_account_raw as 
select distinct account_id, customer_id,account_type,balance,open_date from account_raw;

create or replace table dim_transaction_raw as
select distinct transaction_id,account_id,transaction_type,amount,transaction_date,transaction_time,location,fraud_flag from transaction_raw;

create or replace table dim_fraud_alert_raw as
select distinct transaction_id,account_id,transaction_type,amount,transaction_date,transaction_time,location,fraud_flag,alert_id,risk_level from fraud_alert_raw;


COPY INTO LOAN_RAW
FROM @BANK_STAGE/loan_400.csv
FILE_FORMAT = (
TYPE = CSV
SKIP_HEADER = 1
FIELD_OPTIONALLY_ENCLOSED_BY='"'
);
select *from loan_raw;

create or replace table dim_loan_raw as 
select distinct loan_id,customer_id,loan_amount,interest_rate,loan_status from loan_raw;

create or replace table fact_transaction as 
select transaction_id,account_id,transaction_type,amount,transaction_date,transaction_time,location,fraud_flag from transaction_raw;

create or replace table dim_date as 
select distinct transaction_date,year(transaction_date)as year,month(transaction_date) as month,day(transaction_date) as day from transaction_raw;

show tables;

SELECT C.NAME,A.ACCOUNT_TYPE,F.AMOUNT,F.TRANSACTION_TYPE
FROM FACT_TRANSACTION F
JOIN DIM_ACCOUNT_RAW A
ON F.ACCOUNT_ID = A.ACCOUNT_ID
JOIN DIM_CUSTOMER_RAW C
ON A.CUSTOMER_ID = C.CUSTOMER_ID
LIMIT 20;

SELECT TRANSACTION_TYPE, SUM(AMOUNT) AS TOTAL_AMOUNT
FROM FACT_TRANSACTION
GROUP BY TRANSACTION_TYPE;

create or replace stream transaction_stream 
on table transaction_raw;

create or replace task fraud_task
warehouse = BANKING_WH
schedule = '1 minute'
as insert into fraud_alert_raw
select transaction_id,account_id,transaction_type,amount,transaction_date,transaction_time,location,fraud_flag,uuid_string(),'high' from transaction_stream where amount >100000;

alter task fraud_task resume;

create or replace dynamic table high_risk_transactions
target_lag='1 minute'
warehouse =BANKING_WH
as 
select*from fact_transaction where amount >100000;

create role fraud_analyst;
grant select on table fraud_alert_raw to role fraud_analyst;

create secure view secure_customer_view as 
select customer_id,name,city from dim_customer_raw;

create or replace table json_transaction (data variant);
insert into json_transaction
select parse_json('{
 "transactionId":"TXN001",
 "amount":250000,
 "type":"IMPS"
}');

SELECT
DATA:transactionId,
DATA:amount
FROM JSON_TRANSACTION;

select *from fact_transaction at(offset=>-60*5);

create table fact_transaction_clone
clone fact_transaction;
