--QUESTION 1
WITH added_items AS 
	--CREATE A CTE TO EXTRACT ALL SUCCESSFUL ORDERS AND THEIR ITEMS
	(
	SELECT o.order_id, (e.event_data ->> 'item_id')::INTEGER AS item_id, p.name AS product_name
	FROM alt_school.events e
	LEFT JOIN alt_school.orders o 
	ON e.customer_id =o.customer_id
	JOIN alt_school.products p 
	ON (e.event_data ->> 'item_id')::INTEGER  = p.id 
	WHERE event_data @> '{"event_type":"add_to_cart"}' AND o.order_id IN 
	--the where condition filters this cte to return 
		(
		--this subquery filters the events table and returns a list of order_id with successful checkout
		SELECT (e2.event_data ->> 'order_id')::uuid AS order_id 
		FROM alt_school.events e2 
		WHERE event_data @> '{"status":"success"}' 
		AND event_data @> '{"event_type":"checkout"}'
		)
	),
removed_items AS 
	--CREATE A CTE TO EXTRACT ALL REMOVED ITEMS FROM CARTS THAT WERE CHECKED OUT SUCCESSFULLY
	(
	SELECT o3.order_id, (e3.event_data ->> 'item_id')::INTEGER AS item_id
	FROM alt_school.events e3
	LEFT JOIN alt_school.orders o3 
	ON e3.customer_id =o3.customer_id
	WHERE event_data @> '{"event_type":"remove_from_cart"}' and o3.order_id in
	--filters to get rows with event type removed_from_cart for carts with successful checkout
		(
		--this subquery returns a list of order_id for carts with successful checkout
		SELECT (e4.event_data ->> 'order_id')::uuid AS order_id 
		FROM alt_school.events e4 
		WHERE event_data @> '{"status":"success"}' 
		AND event_data @> '{"event_type":"checkout"}' --filters to return only order_id with successful checkout
		)
	)
SELECT
    ai.item_id AS product_id,
    ai.product_name,
    count(ai.order_id) AS num_times_in_successful_orders
FROM
    added_items ai
LEFT JOIN
	--JOIN BOTH CTE TO GET ITEMS THAT WERE CHECKED OUT SUCCESSFULLY
    removed_items ri ON ai.order_id = ri.order_id AND ai.item_id = ri.item_id
WHERE
    ri.order_id IS null --to filter out removed items
GROUP BY 1,2
ORDER BY num_times_in_successful_orders DESC
LIMIT 1;


--QUESTION 2
WITH added_items AS 
	--this cte returns order information of carts that were successfully checked out
	(
	SELECT 
		o.order_id, 
		e.customer_id, 		
		(e.event_data ->> 'item_id')::INTEGER AS item_id, 
		(e.event_data ->> 'quantity')::INTEGER AS quantity,
		c.location ,
		p.name AS product_name,
		p.price AS price,
		(price*(e.event_data ->> 'quantity')::INTEGER) AS spend
	FROM alt_school.events e
	LEFT JOIN alt_school.orders o 
	ON e.customer_id =o.customer_id
	JOIN alt_school.products p 
	ON (e.event_data ->> 'item_id')::INTEGER = p.id  
	JOIN alt_school.customers c 
	ON e.customer_id = c.customer_id 
	WHERE event_data @> '{"event_type":"add_to_cart"}' AND o.order_id IN 
		(
		--returns a list of successful checkouts order_id  
		SELECT (e2.event_data ->> 'order_id')::uuid AS order_id 
		FROM alt_school.events e2 
		WHERE event_data @> '{"status":"success"}' 
		AND event_data @> '{"event_type":"checkout"}'
		)
	),
removed_items AS 
	--this cte returns order information of items that were removed from a cart that was successfully checked out
	(
	SELECT 
		o3.order_id, 
		e3.customer_id ,
		(e3.event_data ->> 'item_id')::INTEGER AS item_id
	FROM alt_school.events e3
	LEFT JOIN alt_school.orders o3 
	ON e3.customer_id =o3.customer_id
	WHERE event_data @> '{"event_type":"remove_from_cart"}' and o3.order_id in 
		(
		--returns a list of successful checkouts order_id  
		SELECT (e4.event_data ->> 'order_id')::uuid AS order_id 
		FROM alt_school.events e4 
		WHERE event_data @> '{"status":"success"}' 
		AND event_data @> '{"event_type":"checkout"}'
		)
	)
SELECT
    ai.customer_id,
    ai.location,
	sum(ai.spend) as total_spend
 FROM
    added_items ai
LEFT JOIN --join both tables 
    removed_items ri ON ai.order_id = ri.order_id AND ai.item_id = ri.item_id
WHERE
    ri.order_id IS NULL --to filter out removed items
GROUP BY 1,2
ORDER BY total_spend DESC
LIMIT 5;


--QUESTION 3
WITH successful_checkout as
	--returns events with successful checkout
	(
	SELECT event_id,
		   customer_id
	FROM alt_school.events
	--filters the table to return only those that are successful checkouts
	WHERE event_data @> '{"status":"success"}' AND event_data @> '{"event_type":"checkout"}'
	)
SELECT c.location,
	   count(sc.event_id)AS checkout_count
FROM successful_checkout sc
--left join to return all from successful_checkout cte only
LEFT JOIN alt_school.customers c 
ON sc.customer_id = c.customer_id 
GROUP BY c.location
ORDER BY count(sc.customer_id) DESC
LIMIT 1;


--QUESTION 4
WITH abandoned_carts AS 
	--this CTE returns customer_id, event_id and event data for customers that abandoned their carts 
	--excluding 'visits'
	(
    SELECT
        event_id, customer_id, event_data 
    FROM
        alt_school.events
    WHERE
    	--this filters the data to return only those with event_type 'add to cart' and 'remove from cart'
        event_data->>'event_type' IN ('add_to_cart', 'remove_from_cart')
        AND NOT EXISTS 
        	(
        	--this subquery checks if there exists any 'checkout' event for the same customer_id in the events table.
        	--If such an event exists, the subquery returns a row (1) and the NOT EXISTS condition evaluates to false for that customer, 
        	--excluding them from the result set of abandoned carts 
            SELECT 1
            FROM alt_school.events e2
            WHERE e2.customer_id = events.customer_id
            AND e2.event_data->>'event_type' = 'checkout'
        	)
	)
SELECT
    ac.customer_id,
    COUNT(*) AS num_events
FROM
    abandoned_carts ac
GROUP BY ac.customer_id;


--QUESTION 5
WITH successful_checkout AS
	--this cte returns a list of customers with successful checkouts
	(
	SELECT customer_id
	FROM alt_school.events 
	WHERE event_data @> '{"status":"success"}' AND event_data @> '{"event_type":"checkout"}'
	),
customer_visits AS 
	--this cte extracts customers and the number of times they visit
	(
	SELECT
        e2.customer_id,
        COUNT(*) AS visit_count
    FROM
    	alt_school.events e2 
    WHERE
        e2.event_data ->> 'event_type' = 'visit'
    GROUP BY
        e2.customer_id
      )
SELECT ROUND(AVG(cv.visit_count), 2) AS average_visits
FROM
    successful_checkout sc
    --join both cte to filter the table and calculate for only customers with checkout
JOIN customer_visits cv ON sc.customer_id = cv.customer_id;


