SELECT name, posting_date, pos_opening_entry, pos_profile, company, total_sales, total_returns, net_sales, total_expected, total_closing, total_difference
FROM [tabPOS Closing Entry]
WHERE docstatus = 1
  AND (COALESCE(%(company)s, '') = '' OR company = %(company)s)
  AND (COALESCE(%(from_date)s, '') = '' OR posting_date >= %(from_date)s)
  AND (COALESCE(%(to_date)s, '') = '' OR posting_date <= %(to_date)s)
ORDER BY posting_date DESC, name DESC
LIMIT 500;
