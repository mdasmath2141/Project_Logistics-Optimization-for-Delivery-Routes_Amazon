CREATE DATABASE LOGISTICS_OPTIMIZATION_FOR_DELIVERY_ROUTES_AMAZON;
USE LOGISTICS_OPTIMIZATION_FOR_DELIVERY_ROUTES_AMAZON;
show tables;
select * from logistics_optimization_for_delivery_routes_amazon;
select * from orders;
select * from delivery_agents;
select * from routes;
select * from shipment_tracking_table;
select * from warehouses;

				# .........TASK 1 ...........

SET SQL_SAFE_UPDATES = 0;
# 1. Remove Duplicate Order_ID
DELETE o1 FROM Orders o1								
JOIN Orders o2 ON o1.Order_ID = o2.Order_ID
AND o1.Order_Date < o2.Order_Date;

# 2. Replace NULL Traffic_Delay_Min with Route Average
UPDATE Routes r
JOIN (
    SELECT Route_ID, AVG(Traffic_Delay_Min) AS avg_delay
    FROM Routes
    WHERE Traffic_Delay_Min IS NOT NULL
    GROUP BY Route_ID
) t
ON r.Route_ID = t.Route_ID
SET r.Traffic_Delay_Min = t.avg_delay
WHERE r.Traffic_Delay_Min IS NULL;

# 3. Convert Dates to YYYY-MM-DD

UPDATE Orders
SET Order_Date = DATE_FORMAT(Order_Date, '%Y-%m-%d'),
Expected_Delivery_Date = DATE_FORMAT(Expected_Delivery_Date, '%Y-%m-%d'),
Actual_Delivery_Date = DATE_FORMAT(Actual_Delivery_Date, '%Y-%m-%d');

# 4. Flag Invalid Deliveries

ALTER TABLE Orders ADD COLUMN Delivery_Error_Flag VARCHAR(10);

UPDATE Orders
SET Delivery_Error_Flag =
CASE
    WHEN Actual_Delivery_Date < Order_Date THEN 'INVALID'
    ELSE 'VALID'
END;


		#...........TASK 2: Delivery Delay Analysis..............
    
# 1. Calculate Delivery Delay (Days)

SELECT Order_ID,
DATEDIFF(Actual_Delivery_Date, Expected_Delivery_Date) AS Delay_Days
FROM Orders;

# 2. Top 10 Delayed Routes

SELECT 
Route_ID,
AVG(DATEDIFF(Actual_Delivery_Date, Expected_Delivery_Date)) AS Avg_Delay
FROM Orders
GROUP BY Route_ID
ORDER BY Avg_Delay DESC LIMIT 10;

# 3. Rank Orders by Delay Within Each Warehouse

SELECT Order_ID, Warehouse_ID,
DATEDIFF(Actual_Delivery_Date, Expected_Delivery_Date) AS Delay_Days,
RANK() OVER (PARTITION BY Warehouse_ID 
ORDER BY DATEDIFF(Actual_Delivery_Date, Expected_Delivery_Date) DESC) AS Delay_Rank
FROM Orders;



					#................TASK 3: Route Optimization Insights.................
          
	#A.  ROUTE METRICS
    
    
    SELECT o.Route_ID,
    -- 1️. Average Delivery Time (Days)
    ROUND(AVG(DATEDIFF(o.Actual_Delivery_Date, o.Order_Date)), 2) 
        AS Avg_Delivery_Time_Days,

    -- 2️. Average Traffic Delay (Minutes)
    ROUND(AVG(r.Traffic_Delay_Min), 2) 
        AS Avg_Traffic_Delay_Min,

    -- 3️. Average Travel Time (Minutes) - 2 Decimal Places
    ROUND(AVG(r.Average_Travel_Time_Min), 2) 
        AS Avg_Travel_Time_Min,

    -- 4️. Distance-to-Time Efficiency Ratio (2 Decimal Places)
    ROUND(r.Distance_KM / AVG(r.Average_Travel_Time_Min), 3) 
        AS Distance_Time_Efficiency_Ratio
        
FROM Orders o
JOIN Routes r
    ON o.Route_ID = r.Route_ID
GROUP BY 
    o.Route_ID,
    r.Distance_KM;
    
    
			# B.Worst Efficiency Routes
SELECT Route_ID,
ROUND((Distance_KM / Average_Travel_Time_Min),3) AS Efficiency_Ratio
FROM Routes ORDER BY Efficiency_Ratio ASC LIMIT 3;

		# C. Routes with >20% Delayed Shipments
        
SELECT 
Route_ID,
SUM(CASE WHEN Actual_Delivery_Date > Expected_Delivery_Date THEN 1 ELSE 0 END)*100.0 / COUNT(*) AS Delay_Percentage
FROM Orders
GROUP BY Route_ID HAVING Delay_Percentage > 20;






#....................TASK 4: Warehouse Performance...........................
select * from warehouses;

 -- Top 3 Warehouses by Processing Time
 SELECT * FROM Warehouses
ORDER BY Processing_Time_Min DESC LIMIT 3;

 -- Total vs Delayed Shipments
 SELECT Warehouse_ID,
COUNT(*) AS Total_Shipments,
SUM(CASE WHEN Actual_Delivery_Date > Expected_Delivery_Date THEN 1 ELSE 0 END) AS Delayed_Shipments
FROM Orders
GROUP BY Warehouse_ID;

 -- Bottleneck Warehouses (CTE)
 WITH GlobalAvg AS (
    SELECT AVG(Processing_Time_Min) AS Avg_Time FROM Warehouses
)
SELECT * FROM Warehouses, GlobalAvg WHERE Processing_Time_Min > Avg_Time;

 -- Rank Warehouses by On-Time %
 
 SELECT Warehouse_ID,
(SUM(CASE WHEN Actual_Delivery_Date <= Expected_Delivery_Date THEN 1 ELSE 0 END)*100.0 / COUNT(*)) AS OnTime_Percentage,
RANK() OVER (ORDER BY (SUM(CASE WHEN Actual_Delivery_Date <= Expected_Delivery_Date THEN 1 ELSE 0 END)*100.0/ COUNT(*)) DESC) AS Rank_Warehouse
FROM Orders
GROUP BY Warehouse_ID;




 #......................TASK 5: Delivery Agent Performance............................
 
	-- Rank Agents per Route by On-Time %

SELECT 
    da.Agent_ID,
    da.Route_ID,
    ROUND(
        SUM(CASE 
            WHEN o.Actual_Delivery_Date <= o.Expected_Delivery_Date THEN 1 
            ELSE 0 
        END) * 100.0 / COUNT(o.Order_ID), 2
    ) AS OnTime_Percentage,
    
    RANK() OVER (
        PARTITION BY da.Route_ID 
        ORDER BY 
        SUM(CASE 
            WHEN o.Actual_Delivery_Date <= o.Expected_Delivery_Date THEN 1 
            ELSE 0 
        END) * 100.0 / COUNT(o.Order_ID) DESC
    ) AS Agent_Rank

FROM Delivery_Agents da
JOIN Orders o 
    ON da.route_ID = o.route_ID
GROUP BY da.Agent_ID, da.Route_ID;
 
 
 
		-- Find Agents with On-Time % < 80%
 
 SELECT *
FROM (
    SELECT 
        da.Agent_ID,
        
        ROUND(
            SUM(CASE 
                WHEN o.Actual_Delivery_Date <= o.Expected_Delivery_Date THEN 1 
                ELSE 0 
            END) * 100.0 / COUNT(o.Order_ID), 2
        ) AS OnTime_Percentage
    FROM Delivery_Agents da
    JOIN Orders o 
        ON da.route_ID = o.route_ID
    GROUP BY da.Agent_ID 
) AS Agent_Performance
WHERE OnTime_Percentage < 80;



	-- Compare Average Speed of Top 5 vs Bottom 5 Agents
    
WITH Agent_Performance AS (
    SELECT 
        da.Agent_ID,
        da.Avg_Speed_KM_HR,
        SUM(CASE 
            WHEN o.Actual_Delivery_Date <= o.Expected_Delivery_Date THEN 1 
            ELSE 0 
        END) * 100.0 / COUNT(o.Order_ID) AS OnTime_Percentage
    FROM Delivery_Agents da
    JOIN Orders o 
        ON da.route_ID = o.route_ID
    GROUP BY da.Agent_ID, da.Avg_Speed_KM_HR
)

SELECT 
    'Top 5 Agents' AS Category,
    AVG(Avg_Speed_KM_HR) AS Avg_Speed
FROM (
    SELECT * 
    FROM Agent_Performance
    ORDER BY OnTime_Percentage DESC
    LIMIT 5
) t

UNION ALL

SELECT 
    'Bottom 5 Agents' AS Category,
    AVG(Avg_Speed_KM_HR) AS Avg_Speed
FROM (
    SELECT * 
    FROM Agent_Performance
    ORDER BY OnTime_Percentage ASC
    LIMIT 5
) b;





		# ..........................TASK 6 : Shipment Tracking Analytics..................................
SELECT * FROM SHIPMENT_TRACKING_TABLE;

       -- For each order, list the last checkpoint and time.
SELECT Order_ID,
MAX(Checkpoint_Time) AS Last_Checkpoint_Time
FROM Shipment_Tracking_Table
GROUP BY Order_ID;


		-- Most Common Delay Reasons
        
SELECT 
Delay_Reason,
COUNT(*) AS Frequency
FROM Shipment_Tracking_Table
WHERE Delay_Reason <> 'None'
GROUP BY Delay_Reason
ORDER BY Frequency DESC;



	-- Orders with >2 Delayed Checkpoints
    
SELECT 
    o.Order_ID,
    COUNT(st.shipment_ID) AS Delayed_Checkpoints ,
    GROUP_CONCAT(st.Delay_Reason) AS Delay_Reasons
FROM Orders o
JOIN Shipment_Tracking_table st 
    ON o.Order_ID = st.Order_ID
WHERE o.Delivery_Status = 'Delayed'
GROUP BY o.Order_ID
HAVING COUNT(st.shipment_ID) > 2;






		# TASK 7 :.....................Advanced KPI Reporting...................
	
		-- Average Delay per Region
SELECT 
r.Start_Location,
AVG(DATEDIFF(o.Actual_Delivery_Date, o.Expected_Delivery_Date)) AS Avg_Delay
FROM Orders o
JOIN Routes r ON o.Route_ID = r.Route_ID
GROUP BY r.Start_Location;

		-- On-Time Delivery %
SELECT 
(SUM(CASE WHEN Actual_Delivery_Date <= Expected_Delivery_Date THEN 1 ELSE 0 END)*100.0/ COUNT(*)) AS OnTime_Percentage
FROM Orders;


		-- Average Traffic Delay per Route
SELECT 
Route_ID,
AVG(Traffic_Delay_Min) AS Avg_Traffic_Delay
FROM Routes
GROUP BY Route_ID;