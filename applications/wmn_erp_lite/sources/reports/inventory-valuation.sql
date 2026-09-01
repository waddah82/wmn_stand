SELECT warehouse,SUM(actual_qty) AS total_qty,SUM(stock_value) AS stock_value FROM "tabBin" WHERE (%(warehouse)s='' OR warehouse=%(warehouse)s) GROUP BY warehouse ORDER BY stock_value DESC
