--- All Queries and functions used in our work in the order they appear in it

------------------------------ NOT NESTED QUERIES -------------------------------------------------
--- Customers who made more than 100 orders on the first month of 2022 and less on the second

SELECT C.Email, C.[First Name], C.[Last Name], NumOfOrders = COUNT(*)
FROM CUSTOMERS AS C 
JOIN ORDERS AS O ON C.Email = O.[Customer Email] 
JOIN [CONTAINS] AS CO ON O.[Order ID] = CO.[Order ID]
WHERE MONTH(O.[ORDER DT]) = 1
GROUP BY C.Email, C.[First Name], C.[Last Name]
HAVING SUM(QUANTITY) > 10
EXCEPT
SELECT C.Email, C.[First Name], C.[Last Name], NumOfOrders = COUNT(*)
FROM CUSTOMERS AS C 
JOIN ORDERS AS O ON C.Email = O.[Customer Email] 
JOIN [CONTAINS] AS CO ON O.[Order ID] = CO.[Order ID]
WHERE MONTH(O.[ORDER DT]) = 2
GROUP BY C.Email, C.[First Name], C.[Last Name]
HAVING SUM(QUANTITY) > 10
ORDER BY NumOfOrders;


--- Five highest average rated products that were ordered to Conneticut

SELECT TOP 5 R.[Product ID], R.Stars , AVGStars = AVG(R.Stars)
FROM REVIEWS AS R JOIN PRODUCTS AS P ON R.[Product ID] = P.[Product ID]  JOIN CUSTOMERS AS C ON R.[Customer Email] = C.Email
WHERE C.[Address-State] = 'Connecticut'
GROUP BY R.[Product ID], R.Stars
ORDER BY AVGStars DESC


---------------------------------------------  NESTED QUERIES -------------------------------------------------

--- Revenue from products that were sold in specific size in 3 or more orders

SELECT A.[Product ID],A.Size, [Total Revenue] = Sum(A.Amount*T.Price)
FROM TYPES AS T JOIN (SELECT  [Product ID], Size, Amount=Sum(Quantity)
	FROM [CONTAINS]
	GROUP BY  [Product ID], Size
	Having count(*)>3
	) AS A ON T.[Product ID]=A.[Product ID]
GROUP BY A.[Product ID], A.Size


--- Precentage of orders with each category

SELECT P.Category, 
	   CAST(COUNT(*) * 1.0 / (SELECT COUNT(*) FROM ORDERS) AS DECIMAL(10, 2)) AS Proportion
FROM PRODUCTS AS P JOIN [CONTAINS] AS C ON P.[Product ID] = C.[Product ID]
GROUP BY P.Category



--- Customers that are moer then 1 percent of ordered they ordered and left more then 1 review

SELECT Email
FROM CUSTOMERS AS C JOIN ORDERS AS O ON C.Email = O.[Customer Email]
GROUP BY Email 
HAVING COUNT (*) >0.01 * (SELECT COUNT (*) FROM ORDERS)

INTERSECT 

SELECT Email
FROM REVIEWS AS R JOIN CUSTOMERS AS C ON C.Email = R.[Customer Email]
GROUP BY Email
HAVING COUNT (*)>=2

------------------------------ NESTED QUERIES WITH MORE ATTRIBUTES -------------------------------------------------

--- Add to CUSTOMERS table happy/unhappy in a new column based on average rating of order

ALTER TABLE CUSTOMERS
ADD [STATUS] VARCHAR(20);

UPDATE CUSTOMERS
SET [STATUS] = CASE
    WHEN (
        SELECT AVG(R.STARS)
        FROM REVIEWS AS R
        WHERE R.[Customer Email] = CUSTOMERS.Email
    ) <= 3 THEN 'unsatisfied'
    ELSE 'satisfied'
END;


---------------------------------------------- VIEW ------------------------------------------------------------

--- Revenue per product and size

CREATE VIEW V_RevnuePerProductAndSize AS
SELECT T.[Product ID],P.Category,C.[Order ID],C.Size,C.Quantity,T.Price, TotalAmountPerProductSize = T.Price*C.Quantity
FROM PRODUCTS AS P JOIN [CONTAINS] AS C ON P.[Product ID] = C.[Product ID] 
	 JOIN TYPES AS T ON C.Size = T.Size AND P.[Product ID] = T.[Product ID]

SELECT *
FROM V_RevnuePerProductAndSize

DROP VIEW V_RevnuePerProductAndSize



------------------------------------------ FUNCTIONS -----------------------------------------------------------
--- Gets user ID and returns his/her orders


DROP FUNCTION IF EXISTS CUSTOMER_ORDERS;
GO

CREATE FUNCTION CUSTOMER_ORDERS (@CID VARCHAR(40))
    RETURNS TABLE
AS
    RETURN (
        SELECT C.Email, C.[First Name], C.[Last Name], O.[Order ID]
        FROM CUSTOMERS AS C
        JOIN ORDERS AS O ON C.Email = O.[Customer Email]
        WHERE C.Email = @CID
    );

--- Example of function

SELECT *
FROM dbo.CUSTOMER_ORDERS('addison987@gmail.com')



--- Gets product ID and returns average rate of it

CREATE FUNCTION P_Rate (@PID VARCHAR(20))
RETURNS INT
AS
BEGIN
    DECLARE @Rate INT;

    SELECT @Rate = AVG(R.stars)
    FROM PRODUCTS AS P  JOIN REVIEWS AS R ON P.[Product ID] = R.[Product ID]
    WHERE P.[Product ID] = @PID;

    RETURN @Rate;
END

---Example
SELECT RATE = dbo.P_Rate('3')

--------------------------------------------- TRIGGER ----------------------------------------------------------

--- Every time we add a review the average rate of the product will change

ALTER TABLE PRODUCTS 
ADD RATE REAL;

GO


DROP TRIGGER trg_UpdateRate



CREATE TRIGGER trg_UpdateRate ON REVIEWS
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
	UPDATE PRODUCTS
	SET RATE = (
		SELECT CAST(SUM(REVIEWS.STARS)*1.0/COUNT(*)  AS DECIMAL(10, 8))
		FROM REVIEWS
		WHERE PRODUCTS.[Product ID] = REVIEWS.[Product ID]
	)
	FROM PRODUCTS
    WHERE PRODUCTS.[Product ID] IN (
        SELECT [Product ID] FROM inserted
        UNION
        SELECT [Product ID] FROM deleted
    );
END;


---Example
INSERT INTO REVIEWS VALUES
('11','11','2021-05-13 00:00:00.000', 'Was Great', '5', 'scarlett543@gmail.com')

DELETE FROM REVIEWS WHERE [Product ID] = '11' and [Review ID] = '11'

-------------------------------------------- STORDER PROCEDURE -----------------------------------------------------------

--- Put in a product and a new recommended accessory to it, if it doesn't exist add it to recommended table
	

CREATE PROCEDURE SP_AddAccessory
    @ProductID varchar(20),
    @Accessory varchar(100)
AS
	BEGIN
    IF NOT EXISTS (SELECT * FROM RECOMMENDED_ACCESSORIES WHERE [Product ID] = @ProductID AND [Recommended Accessories] = @Accessory)
    BEGIN
        INSERT INTO RECOMMENDED_ACCESSORIES ([Product ID], [Recommended Accessories])
        VALUES (@ProductID, @Accessory);
    END;
END;

EXEC SP_AddAccessory '1', 'Witch Broom'

DROP PROCEDURE SP_AddAccessory

SELECT *
FROM RECOMMENDED_ACCESSORIES
WHERE [Product ID] = '1'


------------------------------------------ VIEWS USED IN THE MARKETING REPORT --------------------------------------------------

--- Total revenue

CREATE VIEW V_TotalRevenue AS
SELECT Revenue = SUM( TotalAmountPerProductSize)
FROM  V_RevnuePerProductAndSize

SELECT *
FROM V_TotalRevenue

DROP VIEW V_TotalRevenue



--- Revenue per category

CREATE VIEW V_RevenuePerCategory AS
SELECT Category, Revenue = Sum(TotalAmountPerProductSize)
FROM V_RevnuePerProductAndSize
GROUP BY Category

SELECT *
FROM V_RevenuePerCategory

DROP VIEW V_RevenuePerCategory


--- Orders per date

CREATE VIEW V_OrdersPerCountry AS
SELECT country,amount= COUNT(*)
FROM CUSTOMERS AS C join ORDERS as o on c.Email=o.[Customer Email] 
GROUP BY country

SELECT *
FROM V_OrdersPerCountry

DROP VIEW V_OrdersPerCountry


--- Average order price

CREATE VIEW V_AvgOrderPrice AS
SELECT AVG_ORDER=(
SELECT    TOTAL_MONEY=SUM(T.Price*C.Quantity)
FROM PRODUCTS AS P JOIN [CONTAINS] AS C ON P.[Product ID] = C.[Product ID] 
	 JOIN TYPES AS T ON C.Size = T.Size AND P.[Product ID] = T.[Product ID]
)/COUNT(*)
FROM ORDERS AS R

select *
from V_AvgOrderPrice


DROP VIEW V_AvgOrderPrice



--- Revenue per product

CREATE VIEW V_RevenuePerProduct AS
SELECT [Product ID], ProductRevenue = SUM(TotalAmountPerProductSize)
FROM V_RevnuePerProductAndSize
GROUP BY [Product ID]

SELECT *
FROM V_RevenuePerProduct

DROP VIEW V_RevenuePerProduct


------------------------------------------------ WINDOW FUNCTIONS --------------------------------------------------------------

--- Rank the products by sales in each category, then devide into 4 groups according to revnue

SELECT  P.[Product ID],P.Category, TOTAL=SUM(Quantity*T.Price),
		Ranking = Rank() 
		       OVER (PARTITION BY Category
					 ORDER BY SUM(Quantity*Price)DESC) ,
		ProductGroup = Ntile(4)
				 OVER (
				 ORDER BY (SUM(Quantity*T.Price))DESC) 
FROM  PRODUCTS AS P JOIN [CONTAINS] AS C ON P.[Product ID]=C.[Product ID] JOIN ORDERS AS O ON O.[Order ID] = C.[Order ID] JOIN TYPES AS T ON T.[Product ID]=P.[Product ID]

GROUP BY  P.Category , P.[Product ID]
ORDER BY P.Category DESC, SUM(Quantity*T.Price)DESC


--- Email, Full name, Cost of last order, average order cost, gap between this order and biggest

SELECT C.Email, C.[First Name], C.[Last Name], 
		Cost= (Quantity*T.Price),OrdersAvgCost=
	AVG(Quantity*T.Price) OVER (PARTITION BY C.Email ORDER BY C.Email 
	ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) , GapFromBiggest=
	MAX(Quantity*T.Price) OVER (PARTITION BY C.Email ORDER BY C.Email )-(Quantity*T.Price) 
	FROM ORDERS AS O JOIN CUSTOMERS AS C ON O.[Customer Email]=C.Email JOIN [CONTAINS] AS CO ON O.[Order ID] = CO.[Order ID] JOIN TYPES AS T ON T.[Product ID]=O.[Order ID]




------------------------------------------------------ INTEGRATED PROCCESS ---------------------------------------------------------

--- Change of price (up or down- 0/1) in a specific category, product and size



--- Create a column that shows the change in price

ALTER TABLE TYPES
ADD [PRECENTEGECHANGE] varchar(20);
GO 

DROP TRIGGER dbo.UPDATETYPES;
GO

---The function in the procedure
--- Gets the product, size and old price and generates the percentage of change that was made

CREATE FUNCTION CALCULATE ( @PRODUCTID varchar(20), @SIZE varchar(20) , @OLDPRICE money )
RETURNS varchar(20)
AS BEGIN 
DECLARE @PRECENTEGE varchar(20) 
SELECT @PRECENTEGE = ((PRICE - @OLDPRICE ) / @OLDPRICE )
FROM TYPES 
WHERE [Product ID] = @PRODUCTID AND SIZE =@SIZE 
RETURN @PRECENTEGE
END



---Trigger in procedure
--- Trigger is activated when percentage is calculated, from DELETED to the place in table

CREATE TRIGGER UPDATETYPES ON TYPES
FOR UPDATE
AS
BEGIN
    UPDATE T
    SET  PRECENTEGECHANGE= C.PERCENTAGE
    FROM TYPES AS T
    INNER JOIN
    (
        SELECT D.[Product ID], D.Size, dbo.CALCULATE(D.[Product ID], D.Size, D.Price) AS PERCENTAGE
        FROM deleted AS D
    ) AS C ON T.[Product ID] = C.[Product ID] AND T.Size = C.Size;
	
END;


--- The final procedure

CREATE PROCEDURE SP_PRICECHANGE (@CATEGORY varchar(50) , @SIZE varchar(20) , @CHANGE REAL , @TYPEOFCHANGE BIT )
AS
BEGIN
    UPDATE T
    SET PRICE = T.PRICE *
        CASE 
            WHEN @TYPEOFCHANGE = 0 THEN (1 - @CHANGE)
            ELSE (1 + @CHANGE)
        END
    FROM TYPES AS T
    INNER JOIN PRODUCTS AS P ON T.[Product ID] = P.[Product ID]
    WHERE P.Category = @CATEGORY
        AND T.Size = @SIZE;
END;


---Example
EXEC SP_PRICECHANGE 'Anime characters','XL', '0.2', '1'



------------------------------------------------------------------ WITH -------------------------------------------------------------

--- Returns a table with data per country- days since last order, active/inatcive , num of orders, Orderes from searches, num of customers and leading category

WITH DaysSinceLastOrderPerCountry AS (
		SELECT C.Country, DaysSinceLastOrder = DATEDIFF (DD, MAX(O.[Order DT]), GETDATE()), Active = (  CASE 
			       WHEN DATEDIFF (DD, MAX(O.[Order DT]), GETDATE()) <= 182 THEN 'Active' 
				   ELSE 'Inactive' END)
		FROM ORDERS AS O JOIN CUSTOMERS AS C ON O.[Customer Email]=C.Email
		GROUP BY C.Country
	),
	SearchesPerCountry AS (
		SELECT C.Country, [Searches Amount] = COUNT(*)
		FROM SEARCHES AS S JOIN CUSTOMERS AS C ON S.[Customer Email] = C.Email
		GROUP BY C.Country
	),
	SearchesToOrdersPerCountry AS (
		SELECT S.Country, [Orders by Search Precentage] = CAST(1.0*S.[Searches Amount] / V.Amount AS DECIMAL(10, 2))
		FROM SearchesPerCountry As S JOIN V_OrdersPerCountry AS V ON S.Country = V.country
	),
	CustomersPerState AS (
		SELECT Country, [Number Of Customers] = COUNT(*)
		FROM CUSTOMERS
		GROUP BY Country
	),
	CategoriesPerState AS (
		SELECT CU.Country, P.Category, [Amount From Category] = COUNT(*)
		FROM PRODUCTS AS P JOIN [CONTAINS] AS CO ON P.[Product ID]= CO.[Product ID] JOIN 
		ORDERS AS O ON CO.[Order ID]=O.[Order ID] JOIN CUSTOMERS AS CU ON O.[Customer Email]=CU.Email
		GROUP BY P.Category, CU.Country
	),
	TopCategoryPerState AS (
		SELECT Country, [Top Category] = Category, Row = ROW_NUMBER () OVER (PARTITION BY Country 
															ORDER BY [Amount From Category] DESC )
		FROM CategoriesPerState
	)
	SELECT D.Country, D.DaysSinceLastOrder, D.Active,[Number Of Orders] = V.amount, 
		   S.[Orders by Search Precentage], C.[Number Of Customers], 
		   T.[Top Category]
	FROM DaysSinceLastOrderPerCountry AS D JOIN SearchesToOrdersPerCountry AS S ON D.Country = S.Country JOIN 
	CustomersPerState AS C ON S.Country = C.Country JOIN V_OrdersPerCountry AS V ON C.Country = V.Country JOIN
	TopCategoryPerState AS T ON V.country = T.Country
	WHERE T.Row = 1
	ORDER BY [Number Of Orders] DESC
