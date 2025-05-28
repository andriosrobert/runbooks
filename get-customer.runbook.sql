SELECT customerid, firstname, lastname, gender, country, phone, email, income
FROM customers
WHERE customerid = {{ .id }}
