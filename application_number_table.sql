
/*

Creating Approved, Declined and Rework metrics for Sanctioning, Validatins and CMS department

*/

SELECT * FROM models.APPLICATION_NUMBER_FACT;

------------------------------------------------------------------------------------------------------------------------------

-- This code will run automatically every morning to update the loan application status

DELETE A.* FROM models.APPLICATION_NUMBER_FACT AS A;

-- Inserting in the fact table

insert into models.APPLICATION_NUMBER_FACT
SELECT
application_number,
status, 
utility,
NULL AS outcome,
action_b,
date_t,
completed_dt,
date_time,
loan_amount
from models.application_number;


-- Creating a new column for rolling average

ALTER TABLE models.APPLICATION_NUMBER_FACT
ADD COLUMN rolling_average int;

UPDATE models.APPLICATION_NUMBER_FACT a
INNER JOIN ( 
select
application_number,
AVG(loan_amount) OVER (ORDER BY date_t ROWS BETWEEN 1 PRECEDING AND CURRENT ROW) as rolling_average
from models.APPLICATION_NUMBER_FACT) b
ON a.application_number = b.application_number
SET a.rolling_average = b.rolling_average
;


-- Setting the outcomes for the approved applications to approved

UPDATE models.APPLICATION_NUMBER_FACT
set
outcome = 'APPROVED'
WHERE status = 'approved' and utility in ('Sanctioning', 'CMS') and action_b = 'Y';



-- Setting the outcome as completed for applications that have being completed in CMS

UPDATE models.APPLICATION_NUMBER_FACT
set
outcome = (select
        'COMPLETED' as outcome
        from ( select
        LEAD(status, 1) OVER (ORDER BY application_number) AS next_task
		#min(status) over (order by application_number rows between 1 following and 1 following) as next_task
        from models.APPLICATION_NUMBER_FACT) a
        where a.next_task is null and utility = 'CMS' and completed_dt is not null)
        where utility = 'CMS';
        
        
       
-- Applications that have through rework in different systems, with a gap of less than 30 seconds between systems

UPDATE models.APPLICATION_NUMBER_FACT a
SET a.outcome = 'REWORK'
WHERE a.utility = 'validations' AND a.status = 'rework'
AND EXISTS (
    SELECT 1
    FROM models.validations_lendnet v
    WHERE a.application_number = v.application_number
    AND (
        a.date_time = v.date_time OR
        TIMESTAMPDIFF(SECOND, a.date_time, v.date_time) <= 30
    )
);
 


-- Setting the outcomes to Declined for the applications that have been worked in two systems and declined

UPDATE models.APPLICATION_NUMBER_FACT a
SET a.outcome = 'DECLINED'
WHERE a.utility = 'validations' AND a.status = 'declined'
AND EXISTS (
    SELECT 1
    FROM models.validations_lendnet v
    WHERE a.application_number = v.application_number
    AND (
        a.date_time = v.date_time OR
        TIMESTAMPDIFF(SECOND, a.date_time, v.date_time) <= 30
    )
);

