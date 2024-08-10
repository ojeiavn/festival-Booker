DROP TABLE IF EXISTS gig_ticket CASCADE;
DROP TABLE IF EXISTS ticket CASCADE;
DROP TABLE IF EXISTS act_gig CASCADE;
DROP TABLE IF EXISTS gig CASCADE;
DROP TABLE IF EXISTS act CASCADE;
DROP TABLE IF EXISTS venue CASCADE;

CREATE TABLE venue(
    venueID SERIAL NOT NULL PRIMARY KEY,
    venuename VARCHAR(100) NOT NULL UNIQUE,
    hirecost INTEGER NOT NULL CHECK (hirecost >= 0),
    capacity INTEGER NOT NULL
);

/*Put your CREATE TABLE statements (and any other schema related definitions) here*/
CREATE TABLE act(
    actID SERIAL NOT NULL PRIMARY KEY,
    actname VARCHAR(100) NOT NULL UNIQUE,
    genre VARCHAR(10),
    standardfee INTEGER NOT NULL CHECK (standardfee >= 0)
);


CREATE TABLE gig(
    gigID SERIAL NOT NULL PRIMARY KEY,
    venueID INTEGER NOT NULL REFERENCES venue(venueID),
    gigtitle VARCHAR(100) NOT NULL,
    gigdatetime TIMESTAMP NOT NULL,
    gigstatus VARCHAR(10) CHECK (gigstatus IN ('Cancelled','GoingAhead'))
);

CREATE table act_gig(
    actID INTEGER NOT NULL REFERENCES act(actID),
    gigID INTEGER NOT NULL REFERENCES gig(gigID),
    actgigfee INTEGER NOT NULL CHECK (actgigfee >= 0),
    ontime TIMESTAMP NOT NULL,
    duration INTEGER CHECK (duration >= 0),
    PRIMARY KEY (actID, gigID, ontime, duration)
);

CREATE TABLE ticket(
    ticketID SERIAL NOT NULL PRIMARY KEY,
    gigID INTEGER NOT NULL REFERENCES gig(gigID),
    pricetype VARCHAR(2) NOT NULL,
    cost INTEGER NOT NULL CHECK (cost >= 0),
    customername VARCHAR(100) NOT NULL,
    customeremail VARCHAR(100) NOT NULL
);

CREATE TABLE gig_ticket(
    gigID INTEGER NOT NULL REFERENCES gig(gigID),
    pricetype VARCHAR(2) NOT NULL,
    price INTEGER NOT NULL CHECK (price >= 0) 
);

--Create a view to have a column to store the finish time
CREATE VIEW act_finish_time AS
SELECT actID,
gigID,
ontime::time,
(ontime::time + duration * interval '1 minute') AS finish_time
FROM act_gig;

--RULE 1
/* Trigger function to prevent overlapping acts on the same gig */
/**/
CREATE OR REPLACE FUNCTION check_act_overlap()
RETURNS TRIGGER AS $$
BEGIN
    -- Check for overlaps with other acts, excluding the current record if it's an update
    IF EXISTS (
        SELECT 1 FROM act_gig 
        WHERE gigID = NEW.gigID 
        AND actID != NEW.actID  -- Exclude the current act from the overlap check
        AND ontime < NEW.ontime + interval '1 minute' * NEW.duration
        AND NEW.ontime < ontime + interval '1 minute' * duration
    ) THEN
        RAISE EXCEPTION 'RULE 1 VIOLATED- Overlapping act';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER overlapping
BEFORE INSERT OR UPDATE ON act_gig
FOR EACH ROW EXECUTE FUNCTION check_act_overlap();

--RULE 2
/* Function to ensure an act performs at only one gig at a time */
/* We want to ensure there are NOT clashing performances at different venues by the same act */
CREATE OR REPLACE FUNCTION check_act_one_gig_at_a_time()
RETURNS TRIGGER AS $$
BEGIN
    IF EXISTS(
        SELECT * FROM act_gig 
        WHERE actID = NEW.actID 
        AND gigID != NEW.gigID
        AND ontime < NEW.ontime + interval '1 minute' * NEW.duration
        AND NEW.ontime < ontime + interval '1 minute' * NEW.duration
    ) THEN
        RAISE EXCEPTION 'RULE 2 VIOLATED- An act can only perform at one gig at a time';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER one_gig_at_a_time
BEFORE INSERT OR UPDATE ON act_gig
FOR EACH ROW EXECUTE FUNCTION check_act_one_gig_at_a_time();

/*Trigger function to make sure an act can only charge one fee per gig

*/
--RULE 3
CREATE OR REPLACE FUNCTION one_fee_per_act()
RETURNS TRIGGER AS $$
BEGIN      
    -- For the INSERT, check if there's any existing fee for the act in the same gig
    -- We use Trigger OPeration (TG_OP) to check which operation fired the trigger
    -- As this query needs to be different for insert and update
    IF TG_OP = 'INSERT' THEN
        IF EXISTS(
            SELECT 1 FROM act_gig
            WHERE actID = NEW.actID
            AND gigID = NEW.gigID
            AND NEW.actgigfee != actgigfee
        ) THEN
            RAISE EXCEPTION 'RULE 3 VIOLATED- An act can only have one fee in a single gig';
        END IF;
    ELSIF TG_OP = 'UPDATE' THEN
    --Check if actgigfee has been changed
        IF NEW.actgigfee IS DISTINCT FROM OLD.actgigfee THEN
        -- For the UPDATE, check if there's any other fee for the same act in the same gig, excluding the record we are trying to update (no self-clash)
            IF EXISTS(
                SELECT 1 from act_gig
                WHERE actID = NEW.actID
                AND gigID = NEW.gigID
                AND NEW.actgigfee != actgigfee
                AND ctid != NEW.ctid
            ) THEN
                RAISE EXCEPTION 'RULE 3 VIOLATED- An act can only have one fee in a single gig';
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER one_fee
BEFORE INSERT OR UPDATE ON act_gig
FOR EACH ROW EXECUTE FUNCTION one_fee_per_act();


-- RULE 12: Making sure no gig starts before 9am
ALTER TABLE gig ADD CONSTRAINT check_gig_start_time CHECK (EXTRACT(HOUR FROM gigdatetime) >= 9);

-- RULE 11
--Making sure rock and pop acts end at 11pm latest, with all other gigs 1am
CREATE OR REPLACE FUNCTION check_gig_end()
RETURNS TRIGGER AS $$
-- actGenre stores the genre of the act the user has inputted into the act table
DECLARE
    actGenre VARCHAR(10);
    gig_date DATE;
BEGIN
    -- Get the genre of the act
    SELECT genre INTO actGenre FROM act WHERE actID = NEW.actID;

    -- Get the date of the gig
    SELECT gigdatetime::date INTO gig_date FROM gig WHERE gigID = NEW.gigID;

    -- Apply the business rule for Rock and Pop genres
    IF actGenre IN ('pop', 'rock') THEN
        -- Calculate end time
        IF (NEW.ontime + NEW.duration * interval '1 minute')::time > '23:00'::time THEN
            RAISE EXCEPTION 'RULE 11 VIOLATED - Rock and Pop acts must end by 11pm';
        END IF;
    ELSE
        -- Check if the act ends on the next day
        IF (NEW.ontime + NEW.duration * interval '1 minute')::date > gig_date THEN
            -- If the act ends on the next day, check if it ends after 1:00 am
            IF (NEW.ontime + NEW.duration * interval '1 minute')::time > '01:00'::time THEN
                RAISE EXCEPTION 'RULE 11 VIOLATED - All gigs which are not rock and pop must end by 1am.';
            END IF;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER gig_ending_time
BEFORE INSERT OR UPDATE ON act_gig
FOR EACH ROW EXECUTE FUNCTION check_gig_end();

--RULE 4: An act can't perform for more than 90 minutes without a 15 minute break
CREATE OR REPLACE FUNCTION ninety_min_check()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.duration > 90 OR EXISTS(
        SELECT * 
        FROM act_gig
        WHERE actID = NEW.actID
        AND gigID = NEW.gigID
        AND ctid != NEW.ctid
        AND (
            (NEW.ontime > ontime AND (NEW.ontime - interval '15 minutes' <= ontime + interval '1 minute' * duration)) OR
            (NEW.ontime < ontime AND (ontime - interval '15 minutes' <= NEW.ontime + interval '1 minute' * NEW.duration))
        )
    )
    THEN
        RAISE EXCEPTION 'RULE 4 VIOLATED- An act cannot perform for more than 90 minutes without a 15 minute break.';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER ninety_min_rule
BEFORE INSERT OR UPDATE ON act_gig
FOR EACH ROW EXECUTE FUNCTION ninety_min_check();
--RULE 5
--Acts can perform at different gigs but they must be at least 60 mins apart
CREATE OR REPLACE FUNCTION act_gig_perform()
RETURNS TRIGGER AS $$
BEGIN
    IF EXISTS(
        SELECT * 
        FROM act_gig
        WHERE actID = NEW.actID
        AND ctid != NEW.ctid
        AND gigID != NEW.gigID
        AND (
            (NEW.ontime > ontime AND (NEW.ontime - interval '60 minutes' < ontime + interval '1 minute' * duration)) OR
            (NEW.ontime < ontime AND (ontime - interval '60 minutes' < NEW.ontime + interval '1 minute' * NEW.duration))
        )
    ) THEN
        RAISE EXCEPTION 'RULE 5 VIOLATED- An act requires 60 minutes to travel to the new gig venue.';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER sixty_mins_travel
BEFORE INSERT OR UPDATE ON act_gig
FOR EACH ROW EXECUTE FUNCTION act_gig_perform();







--RULE 6: Venues can be used by multiple gigs on the same day 
--(provided it's not at the same time) but need a 180 minute gap between gigs (so that staff can tidy the venue).

CREATE OR REPLACE FUNCTION venue_has_no_overlapping_gigs()
RETURNS TRIGGER AS $$
DECLARE 
    existing_gig RECORD;
    new_end_time TIMESTAMP;
BEGIN
    -- Get the end time of the new gig
    SELECT (MAX(ontime) + duration * interval '1 minute') INTO new_end_time
    FROM act_gig
    WHERE gigID = NEW.gigID
    GROUP BY duration;

    FOR existing_gig IN 
        SELECT act_gig.ontime, (act_gig.ontime + act_gig.duration * interval '1 minute') as endtime 
        FROM act_gig 
        JOIN gig ON act_gig.gigID = gig.gigID
        WHERE gig.venueID = NEW.venueID 
        AND gig.gigstatus != 'Cancelled'
        AND gig.gigID != NEW.gigID
    LOOP
        -- Check if new gig overlaps with existing gig considering 180 minutes gap
        IF NEW.gigdatetime <= existing_gig.endtime + interval '180 minutes' AND
           new_end_time > existing_gig.ontime - interval '180 minutes' THEN
            RAISE EXCEPTION 'RULE 6 VIOLATED- Overlapping gig times detected at the same venue- they must be at least 180 minutes apart too.';
        END IF;
    END LOOP;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;




CREATE TRIGGER no_gig_overlaps
BEFORE INSERT OR UPDATE ON gig
FOR EACH ROW EXECUTE FUNCTION venue_has_no_overlapping_gigs();




--RULE 7
CREATE OR REPLACE FUNCTION check_gig_interval()
RETURNS TRIGGER AS $$
DECLARE
    prev_finish TIMESTAMP;
    next_start TIMESTAMP;
BEGIN
    -- Find the finish time of the act before the current one
    SELECT MAX(ontime + interval '1 minute' * duration) INTO prev_finish
    FROM act_gig
    WHERE gigID = NEW.gigID AND ontime < NEW.ontime;

    -- Find the start time of the act after the current one
    SELECT MIN(ontime) INTO next_start
    FROM act_gig
    WHERE gigID = NEW.gigID AND ontime > NEW.ontime;

    -- Check if the gap before the new act is more than 20 minutes
    IF (NEW.ontime - prev_finish) > interval '20 minutes' AND prev_finish IS NOT NULL THEN
        RAISE EXCEPTION 'RULE 7 VIOLATED- More than 20 minutes interval before the act';
    END IF;

    -- Check if the gap after the new act is more than 20 minutes
    IF (next_start - (NEW.ontime + interval '1 minute' * NEW.duration)) > interval '20 minutes' AND next_start IS NOT NULL THEN
        RAISE EXCEPTION 'RULE 7 VIOLATED- More than 20 minutes interval after the act';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER twenty_min_max_interval
AFTER INSERT OR UPDATE ON act_gig
FOR EACH ROW EXECUTE FUNCTION check_gig_interval();



-- RULE 8
--Checks the first act in a gig has the same start time as the gig itself
CREATE OR REPLACE FUNCTION check_first_act_start_time()
RETURNS TRIGGER AS $$
BEGIN
    -- Check if there are no earlier acts for this gig
    IF NOT EXISTS(
        SELECT 1
        FROM act_gig
        WHERE gigID = NEW.gigID AND ontime < NEW.ontime
    ) THEN
        -- If this is the first act, ensure its start time matches the gig's start time
        IF NEW.ontime != (SELECT gigdatetime FROM gig WHERE gigID = NEW.gigID) THEN
            RAISE EXCEPTION 'RULE 8 VIOLATED- The first act in a gig must have the same start time as the gig itself.';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER first_act
BEFORE INSERT OR UPDATE ON act_gig
FOR EACH ROW EXECUTE FUNCTION check_first_act_start_time();


-- RULE 9 Check if the tickets bought exceeds the capacity of the venue for a given gig
CREATE OR REPLACE FUNCTION limit_tickets_sold()
RETURNS TRIGGER AS $$
DECLARE
    venue_capacity INT;
    ticket_count INT;
BEGIN
    SELECT COUNT(*) INTO ticket_count FROM ticket WHERE ticket.gigID = NEW.gigID;

    SELECT venue.capacity INTO venue_capacity FROM gig 
    JOIN venue ON gig.venueID = venue.venueID 
    WHERE gig.gigID = NEW.gigID;
       
    IF (ticket_count > venue_capacity) THEN
        RAISE EXCEPTION 'RULE 9 VIOLATED - Tickets sold exceeds venue capacity.';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER limit_tickets
BEFORE INSERT OR UPDATE ON ticket
FOR EACH ROW EXECUTE FUNCTION limit_tickets_sold();

/* ---------LEAVE THIS COMMENTED OUT------------------
-- RULE 10: Make sure each gig is at least 60 minutes long
CREATE OR REPLACE FUNCTION check_gig_duration()
RETURNS TRIGGER AS $$
DECLARE
    gig_start TIMESTAMP;
    gig_end TIMESTAMP;
    latest_act_duration INTEGER;
BEGIN
    -- Find the earliest start time of acts in the gig
    SELECT MIN(ontime) INTO gig_start FROM act_gig WHERE gigID = NEW.gigID;

    -- Find the latest act's end time
    SELECT ontime, duration INTO gig_end, latest_act_duration
    FROM act_gig
    WHERE gigID = NEW.gigID AND ontime = (SELECT MAX(ontime) FROM act_gig WHERE gigID = NEW.gigID);

    -- Calculate the end time of the latest act
    gig_end := gig_end + latest_act_duration * interval '1 minute';

    -- Check if the total duration is less than 60 minutes
    IF gig_end - gig_start < interval '60 minutes' THEN
        RAISE EXCEPTION 'RULE 10 VIOLATED - A gig should be at least 60 minutes long';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--This trigger is DEFERRABLE, so will only execute once a transaction has been committed
CREATE TRIGGER check_gig_duration_trigger
AFTER INSERT OR UPDATE ON act_gig
--DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_gig_duration();
*/

-- Check if the adult ticket costs something
--Create trigger
CREATE OR REPLACE FUNCTION check_adult_cost()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.pricetype = 'A' AND NEW.cost <= 0 THEN
        RAISE EXCEPTION 'Adult ticket must have a cost';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER adult_price_check
BEFORE INSERT OR UPDATE ON ticket
FOR EACH ROW EXECUTE FUNCTION check_adult_cost();

--Check if the customer ticket is of a valid type
CREATE OR REPLACE FUNCTION check_ticket_type()
RETURNS TRIGGER AS $$
BEGIN
    -- Check if the pricetype of the new ticket is not available for the specified gig
    IF NOT EXISTS (
        SELECT 1 
        FROM gig_ticket
        WHERE gig_ticket.gigID = NEW.gigID
        AND gig_ticket.pricetype = NEW.pricetype
    )
    THEN
        RAISE EXCEPTION 'Invalid ticket type for this gig';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER ticket_type_check
BEFORE INSERT OR UPDATE ON ticket
FOR EACH ROW EXECUTE FUNCTION check_ticket_type();



--Checks an email is unique to a customername
DROP FUNCTION IF EXISTS check_email_unique;
CREATE OR REPLACE FUNCTION check_email_unique()
RETURNS TRIGGER AS $$
BEGIN
    -- Check if the email is already in use with a different customer name
    IF EXISTS (
        SELECT 1
        FROM ticket
        WHERE customeremail = NEW.customeremail
        AND customername != NEW.customername
    ) THEN
        RAISE EXCEPTION 'Email already in use with a different customer name';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER email_unique
BEFORE INSERT OR UPDATE ON ticket
FOR EACH ROW EXECUTE FUNCTION check_email_unique();

--Task 3: Booking a ticket
DROP FUNCTION IF EXISTS book_ticket;
CREATE OR REPLACE PROCEDURE book_ticket(
    gig_id INT,
    customername VARCHAR(100),
    customeremail VARCHAR(100),
    tickettype VARCHAR(2)
)
LANGUAGE plpgsql
AS $$
DECLARE
    ticket_price INT;
BEGIN
    -- Get ticket price
    SELECT price INTO ticket_price FROM gig_ticket WHERE gigID = gig_id AND pricetype = tickettype;

    -- Check if the gig exists and the ticket type is valid (this would be handled by the check_ticket_type trigger anyway)
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invalid gigID or ticket type';
    END IF;

    
    IF EXISTS( SELECT 1 FROM gig g1 WHERE g1.gigID = gig_id AND gigstatus = 'Cancelled')
    THEN
        RAISE EXCEPTION 'Gig is cancelled';
    END IF;
    -- Insert the ticket
    INSERT INTO ticket(gigID, pricetype, cost, customername, customeremail)
    VALUES (gig_id, tickettype, ticket_price, customername, customeremail);

    COMMIT;
END;
$$;

--Task 4
--Create a composite type
DROP TYPE IF EXISTS cancel_act_gig_result CASCADE;
CREATE TYPE cancel_act_gig_result AS (
    actname VARCHAR(100),
    ontime TIME,
    finish_time TIME,
    customeremail VARCHAR(100)
);

--Procedure to cancel an act's performances in a gig
DROP FUNCTION IF EXISTS cancel_act_in_gig;
CREATE OR REPLACE FUNCTION cancel_act_in_gig(act_id INTEGER, gig_id INTEGER)
RETURNS SETOF cancel_act_gig_result AS $$
DECLARE 
    result cancel_act_gig_result;
    total_act_duration INTEGER := 0;
    act_count INTEGER := 0;
    time_shift INTEGER := 0;
    act_record RECORD;
    last_act_id INTEGER;
BEGIN
    ALTER TABLE act_gig DISABLE TRIGGER first_act;
    ALTER TABLE act_gig DISABLE TRIGGER twenty_min_max_interval;
    ALTER TABLE ticket DISABLE TRIGGER adult_price_check;
    ALTER TABLE act_gig DISABLE TRIGGER ninety_min_rule;

    --Count all the distinct actIDs in the act table
    SELECT COUNT(DISTINCT actID) INTO act_count FROM act_gig WHERE gigID = gig_id;
    SELECT actID INTO last_act_id FROM act_gig WHERE gigID = gig_id ORDER BY act_gig.ontime DESC LIMIT 1;

    -- If the act to be deleted is the headline act of the gig, delete the whole gig
    -- And set the cost of that gig's ticket to 0
    IF act_count = 1 OR act_id = last_act_id THEN
        UPDATE gig SET gigstatus = 'Cancelled' WHERE gigID = gig_id;
        UPDATE ticket SET cost = 0 WHERE gigID = gig_id;
        RETURN QUERY SELECT NULL::VARCHAR(100), NULL::TIME, NULL::TIME, customeremail
        FROM ticket WHERE gigID = gig_id;
    ELSE
        -- An act may have multiple performances in a gig
        FOR act_record IN SELECT * FROM act_gig WHERE gigID = gig_id ORDER BY ontime LOOP
            IF act_record.actID = act_id THEN
                -- Add the duration to the total shift for deleted acts
                time_shift := time_shift + act_record.duration;
                -- Delete the act's performance
                DELETE FROM act_gig WHERE actID = act_id AND gigID = gig_id AND ontime = act_record.ontime;
            ELSE
                -- Update ontime for the remaining acts
                UPDATE act_gig SET ontime = act_gig.ontime - (interval '1 minute' * time_shift) 
                WHERE actID = act_record.actID AND gigID = gig_id AND ontime = act_record.ontime;
            END IF;
        END LOOP;
    END IF;

    ALTER TABLE act_gig ENABLE TRIGGER first_act;
    ALTER TABLE act_gig ENABLE TRIGGER twenty_min_max_interval;
    ALTER TABLE ticket ENABLE TRIGGER adult_price_check;
    ALTER TABLE act_gig ENABLE TRIGGER ninety_min_rule;

    -- Return the updated act information
    RETURN QUERY SELECT a.actname, aft.ontime, aft.finish_time, NULL::VARCHAR(100) 
                 FROM act_finish_time aft 
                 JOIN act a ON aft.actID = a.actID 
                 JOIN gig g ON aft.gigID = g.gigID 
                 WHERE g.gigID = gig_id 
                 ORDER BY aft.ontime;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE EXCEPTION 'The act was not found in the gig';
    WHEN OTHERS THEN
        RAISE;
END;
$$ LANGUAGE plpgsql;

--This is called when a business rule is violated by cancel_act_in_gig(), to cancel the whole gig
DROP FUNCTION IF EXISTS cancel_gig;
CREATE OR REPLACE FUNCTION cancel_gig(gig_id INTEGER)
RETURNS SETOF cancel_act_gig_result AS $$
BEGIN
    ALTER TABLE ticket DISABLE TRIGGER adult_price_check;

    -- Check if the gig exists
    IF NOT EXISTS(SELECT 1 FROM gig WHERE gigID = gig_id) THEN
        RAISE EXCEPTION 'The gig with ID % was not found', gig_id;
    END IF;

    -- Update the gig status to 'Cancelled'
    UPDATE gig SET gigstatus = 'Cancelled' WHERE gigID = gig_id;

    -- Set the cost of all tickets for this gig to 0
    UPDATE ticket SET cost = 0 WHERE gigID = gig_id;

    -- Return the distinct emails of customers who have tickets for this gig
    RETURN QUERY SELECT NULL::VARCHAR(100), NULL::TIME, NULL::TIME, customeremail 
    FROM ticket WHERE gigID = gig_id ORDER BY ticket.customeremail;
    
    ALTER TABLE ticket ENABLE TRIGGER adult_price_check;

EXCEPTION
--Catch additional errors 
    WHEN OTHERS THEN
        RAISE;
END;
$$ LANGUAGE plpgsql;


-- TASK 5: Create a function to calculate tickets needed to sell for each gig
DROP FUNCTION IF EXISTS get_tickets_to_sell;
CREATE OR REPLACE FUNCTION get_tickets_to_sell()
RETURNS TABLE(gig_id INTEGER, tickets_to_sell INTEGER) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        gig.gigID, 
        CEIL(
            ((SUM(DISTINCT act_gig.actgigfee) + venue.hirecost) / gig_ticket.price) - 
            (SELECT COALESCE(COUNT(ticket.ticketID), 0) FROM ticket WHERE gig.gigID = ticket.gigID)
        )::INTEGER AS tickets_to_sell
    FROM 
        gig
        INNER JOIN act_gig ON gig.gigID = act_gig.gigID
        INNER JOIN act ON act_gig.actID = act.actID
        INNER JOIN venue ON gig.venueID = venue.venueID
        INNER JOIN gig_ticket ON gig.gigID = gig_ticket.gigID
    WHERE 
        gig_ticket.pricetype = 'A' 
    GROUP BY 
        gig.gigID, gig_ticket.price, venue.hirecost
    ORDER BY 
        gig.gigID;
END;
$$ LANGUAGE plpgsql;



-- Task 6: Calculate the total number of tickets sold by each act, categorized by year and total.
-- This function retrieves the total number of tickets sold by each act when they are the headline act.
-- The results are separated by year and include a total count across all years.DROP FUNCTION IF EXISTS calculate_headline_act_ticket_sales;
DROP FUNCTION IF EXISTS calculate_headline_act_ticket_sales;
CREATE OR REPLACE FUNCTION calculate_headline_act_ticket_sales()
RETURNS TABLE(act_name VARCHAR, year VARCHAR, tickets_sold INTEGER) AS $$
BEGIN
    RETURN QUERY
    WITH total_tickets_per_act AS (
        SELECT 
            a.actname, 
            COUNT(t.ticketID)::INTEGER AS total_tickets
        FROM 
            (SELECT actID, gigID, 
                    ROW_NUMBER() OVER (PARTITION BY gigID ORDER BY ontime DESC) AS act_order 
             FROM act_gig) AS act_order_time 
            JOIN ticket t ON act_order_time.gigID = t.gigID
            JOIN gig g ON act_order_time.gigID = g.gigID
            JOIN act a ON act_order_time.actID = a.actID
        WHERE 
            act_order_time.act_order = 1 AND g.gigstatus != 'Cancelled'
        GROUP BY a.actname
    )
    SELECT actname, TRIM(year_label)::VARCHAR AS year, tickets_sold_count AS tickets_sold
    FROM (
        -- Yearly ticket sales data
        SELECT 
            a.actname, 
            TRIM(TO_CHAR(EXTRACT(YEAR FROM g.gigdatetime), '9999'))::VARCHAR AS year_label, -- Alias for year
            COUNT(t.ticketID)::INTEGER AS tickets_sold_count -- Alias for tickets sold
        FROM 
            (SELECT actID, gigID, 
                    ROW_NUMBER() OVER (PARTITION BY gigID ORDER BY ontime DESC) AS act_order 
             FROM act_gig) AS act_order_time 
            JOIN ticket t ON act_order_time.gigID = t.gigID
            JOIN gig g ON act_order_time.gigID = g.gigID
            JOIN act a ON act_order_time.actID = a.actID
        WHERE 
            act_order_time.act_order = 1 AND g.gigstatus != 'Cancelled'
        GROUP BY 
            a.actname, year_label

        UNION ALL

        -- Total ticket sales data
        SELECT 
            TRIM(actname) AS actname, 
            TRIM('Total'::VARCHAR) AS year_label, 
            total_tickets AS tickets_sold_count
        FROM total_tickets_per_act
    ) AS combined_data
    ORDER BY 
        (SELECT total_tickets FROM total_tickets_per_act WHERE actname = combined_data.actname), 
        (year_label = 'Total'), 
        year_label;
END;
$$ LANGUAGE plpgsql;






-- Task 7: Identify regular customers who frequently attend gigs of specific acts.
-- This function finds customers who have attended gigs featuring particular headline acts regularly.
-- It returns each act along with customers who have attended their gigs in multiple years.
DROP FUNCTION IF EXISTS regular_customers;
CREATE OR REPLACE FUNCTION regular_customers()
RETURNS TABLE(act_name VARCHAR, customer_name TEXT, ticket_count BIGINT) AS $$
BEGIN
    RETURN QUERY
    WITH headline_acts AS (
        SELECT 
            a.actname, 
            g.gigID
        FROM 
            (SELECT actID, gigID, 
                    ROW_NUMBER() OVER (PARTITION BY gigID ORDER BY ontime DESC) AS act_order 
             FROM act_gig) AS act_order_time 
            JOIN gig g ON act_order_time.gigID = g.gigID
            JOIN act a ON act_order_time.actID = a.actID
        WHERE 
            act_order_time.act_order = 1 AND g.gigstatus != 'Cancelled'
        GROUP BY a.actname, g.gigID
    ),
     customer_attendance AS (
    SELECT 
        t.customername,
        h.actname,
         COUNT(DISTINCT EXTRACT(YEAR FROM g.gigdatetime)) AS distinct_years_count
    FROM 
        ticket t 
        JOIN gig g ON t.gigID = g.gigID
        JOIN headline_acts h ON t.gigID = h.gigID
    GROUP BY 
        t.customername, h.actname
    HAVING COUNT(DISTINCT EXTRACT(YEAR FROM g.gigdatetime)) > 1
)
    SELECT  
        h.actname AS act_name, 
        COALESCE(MAX(c.customername), '[None]') AS customer_name,
        MAX(c.distinct_years_count) AS ticket_count
    FROM headline_acts h
    LEFT JOIN 
        customer_attendance c ON h.actname = c.actname
    GROUP BY h.actname, c.customername
    ORDER BY h.actname, MAX(c.distinct_years_count) DESC;
END;
$$ LANGUAGE plpgsql;


-- Task 8: Determine economically feasible gigs for specific acts at various venues.
-- This view calculates potential revenue, costs, and ticket requirements for each act-venue combination.
-- It helps in deciding whether booking an act at a certain venue is financially viable.
CREATE VIEW revenue_and_gigs AS
    SELECT 
        v.venuename,
        a.actname,
        (avg_ticket_cost * v.capacity) AS revenue,
        (a.standardfee + v.hirecost) AS cost,
        (avg_ticket_cost * v.capacity >= a.standardfee + v.hirecost) AS feasible_act,
        (a.standardfee + v.hirecost) / avg_ticket_cost AS tickets_required
    FROM venue v
    --Cross Join ensures combinattion of ALL venues and acts
    CROSS JOIN act a,
    (SELECT AVG(cost)::INTEGER AS avg_ticket_cost FROM ticket t
     JOIN gig g ON t.gigid = g.gigid WHERE g.gigstatus != 'Cancelled') AS avg_cost
    ORDER BY v.venuename, tickets_required DESC;

-- This function returns a table of venues, acts, and the minimum number of tickets needed to break even.
-- It helps in planning economically feasible gigs with a single act at a given venue.
DROP FUNCTION IF EXISTS feasible_gigs;
CREATE OR REPLACE FUNCTION feasible_gigs() 
RETURNS TABLE(venue_name VARCHAR, act_name VARCHAR, tickets_required INTEGER) AS $$
BEGIN
    RETURN QUERY
    SELECT venuename, actname, revenue_and_gigs.tickets_required  FROM revenue_and_gigs WHERE feasible_act = true;
END;
$$ LANGUAGE plpgsql;