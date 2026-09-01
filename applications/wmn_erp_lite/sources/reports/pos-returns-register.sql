SELECT name, posting_date, customer, return_against, grand_total, paid_amount, outstanding_amount
FROM [tabPOS Invoice]
WHERE docstatus = 1 AND is_return = 1
  AND (COALESCE(%(company)s, '') = '' OR company = %(company)s)
  AND (COALESCE(%(from_date)s, '') = '' OR posting_date >= %(from_date)s)
  AND (COALESCE(%(to_date)s, '') = '' OR posting_date <= %(to_date)s)
ORDER BY posting_date DESC, name DESC
LIMIT 500;
