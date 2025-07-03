import pandas as pd
import json
import os
import re
from datetime import datetime
import warnings

warnings.filterwarnings("ignore")

def find_header_row(df, expected_columns):
    # Loop through each row and check for the header identifier
    for i in df.index:
        if all(col in df.iloc[i].values for col in expected_columns):
            return i
    return None  # Return None if header row is not found

def find_data_start(df):
    # Loop through each row
    for i in df.index:
        row_values = df.iloc[i].values
        # Check if the row matches the characteristic of the data rows
        if is_data_row(row_values):
            return i
    return None  # Return None if data start is not found

def is_data_row(row_values):
    # Define the characteristic of the data rows
    # For example, if all data rows have at least 5 non-empty cells:
    return sum(1 for value in row_values if pd.notna(value)) >= 5

def process_excel_file(file_path, expected_columns):
    # Extract the date from the filename
    date_str = re.search(r'\d{8}', file_path)
    if date_str is not None:
        payment_date = datetime.strptime(date_str.group(), '%Y%m%d').date()
    else:
        payment_date = None

    # Load the workbook
    workbook = pd.ExcelFile(file_path)
    # Load the first sheet into a DataFrame
    sheet_df = workbook.parse(workbook.sheet_names[0], header=None)

    # Find the start of the data
    data_start = find_data_start(sheet_df)
    if data_start is None:
        raise ValueError("Start of payment data not found.")

    # Read the Excel file from the data start onwards
    df = pd.read_excel(file_path, header=data_start)

    # Drop the "Unnamed: 1" column if it exists
    df = df.drop(columns=["Unnamed: 1", "Avi", "Adress"], errors="ignore")

    # Replace newline characters in column names
    df.columns = df.columns.str.replace('\n', ' ')

    # Rename the columns for clarity
    df.rename(columns=expected_columns, inplace=True)

    # Drop the "account_number" column if it exists
    df = df.drop(columns=["account_number"], errors="ignore")

    # Convert the "message" field to string and replace NaN with False
    df['message'] = df['message'].astype(str).replace('nan', '')

    # Filter out rows with missing 'debtor_name'
    df = df[pd.notna(df['debtor_name'])]

    # Add the payment date as a new column
    df['payment_date'] = payment_date.strftime('%Y-%m-%d')

    # Ensure the 'reference' column is of type string
    df['reference'] = df['reference'].astype(str).replace('nan', '')

    # Convert the DataFrame to a list of dictionaries
    payments = df.to_dict(orient='records')

    # Format the amount to two decimal places
    for payment in payments:
        payment['total_amount'] = "{:.2f}".format(payment['total_amount'])

    return payments

# Example usage
payments = []
expected_columns = {
    'Avsändare': 'debtor_name',
    'Betalningsreferens': 'reference',
    'Bankgironummer/ Avinummer': 'account_number',
    'Belopp': 'total_amount',
    'Adress': 'address',
    'Meddelande': 'message'
}

for filename in os.listdir('./transactions/'):
    if filename.endswith('.xlsx') and not filename.startswith('~$'):
        file_path = os.path.join('./transactions/', filename)
        try:
            payments.extend(process_excel_file(file_path, expected_columns))
        except ValueError as e:
            print(f"Error processing {filename}: {e}")

json_payments = json.dumps(payments, indent=4, ensure_ascii=False)
print(json_payments)