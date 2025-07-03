from ticktick.oauth2 import OAuth2
from ticktick.api import TickTickClient
import re
import time

client_id = '84bz7TO6S54molh6Tf'
client_secret = '***REMOVED***'

redirect_uri = 'http://localhost'  # Ensure this matches your registered redirect URI

# Initialize the OAuth2 client
auth_client = OAuth2(client_id=client_id, client_secret=client_secret, redirect_uri=redirect_uri)

# Initialize the TickTick client with username and password
username = 'branstrom@gmail.com'
password = '***REMOVED***'

client = TickTickClient(username=username, password=password, oauth=auth_client)

# Fetch all tasks
tasks = client.state['tasks']
for task in tasks:
    print(f"Task ID: {task['id']}, Title: {task['title']}")

# Function to clean task titles
def clean_title(title):
    # Remove empty brackets at the start
    cleaned_title = re.sub(r'^\[\s*\]', '', title)
    # Remove dates in the format YYYY-MM-DD
    cleaned_title = re.sub(r'\d{4}-\d{2}-\d{2}', '', cleaned_title)
    # Remove any leading/trailing spaces
    cleaned_title = cleaned_title.strip()
    return cleaned_title

# Update task titles
for task in tasks:
    task_id = task['id']
    original_title = task['title']
    new_title = clean_title(original_title)

    if original_title != new_title:
        task['title'] = new_title
        print(f"Updating task {task_id}: {original_title} -> {new_title}...")
        client.task.update(task)
        print(f"Updated task {task_id}: {original_title} -> {new_title}")
        time.sleep(0.3)

print("Task titles updated.")
exit()

import re
import requests
# from ticktick.oauth2 import OAuth2
# from ticktick.api import TickTickClient
import webbrowser
import json

client_id = '84bz7TO6S54molh6Tf'
client_secret = '***REMOVED***'

redirect_uri = 'http://localhost'  # Ensure this matches your registered redirect URI

auth_url = 'https://ticktick.com/oauth/authorize'
token_url = 'https://ticktick.com/oauth/token'

# Step 1: Get authorization code
params = {
    'client_id': client_id,
    'redirect_uri': redirect_uri,
    'response_type': 'code',
    'scope': 'tasks:write tasks:read'
}

response = requests.get(auth_url, params=params)
print("Please go to this URL and authorize access: ", response.url)

# After authorizing, TickTick will redirect to the redirect_uri with a code in the URL
redirected_url = input("Enter the URL you were redirected to: ")
authorization_code = re.search('code=([^&]*)', redirected_url).group(1)

# Step 2: Exchange authorization code for access token
data = {
    'client_id': client_id,
    'client_secret': client_secret,
    'code': authorization_code,
    'grant_type': 'authorization_code',
    'redirect_uri': redirect_uri
}

token_response = requests.post(token_url, data=data)
token_info = token_response.json()
print(json.dumps(token_info, indent=4))
access_token = token_info['access_token']
#refresh_token = token_info['refresh_token']

#print("Access Token: ", access_token)
#print("Refresh Token: ", refresh_token)

# Fetch projects to get the Inbox ID
projects_url = 'https://api.ticktick.com/open/v1/project'
headers = {
    'Authorization': f'Bearer {access_token}'
}

projects_response = requests.get(projects_url, headers=headers)
projects = projects_response.json()
print(json.dumps(projects, indent=4))

inbox_id = next((project['id'] for project in projects if project['name'] == 'Inbox'), None)
print("Inbox ID: ", inbox_id)

# Fetch tasks from Inbox
tasks_url = f'https://api.ticktick.com/open/v1/project/{inbox_id}/data'
tasks_response = requests.get(tasks_url, headers=headers)
tasks = tasks_response.json()
print(json.dumps(tasks, indent=4))
exit()

# Function to clean task titles
def clean_title(title):
    # Remove empty brackets at the start
    cleaned_title = re.sub(r'^\[\s*\]', '', title)
    # Remove dates in the format YYYY-MM-DD
    cleaned_title = re.sub(r'\d{4}-\d{2}-\d{2}', '', cleaned_title)
    # Remove any leading/trailing spaces
    cleaned_title = cleaned_title.strip()
    return cleaned_title

# Update task titles
for task in tasks:
    task_id = task['id']
    original_title = task['title']
    new_title = clean_title(original_title)

    if original_title != new_title:
        task['title'] = new_title
        update_task_url = f'https://api.ticktick.com/open/v1/task/{task_id}'
        update_response = requests.put(update_task_url, headers=headers, json=task)
        print(f"Updated task {task_id}: {original_title} -> {new_title}")

print("Task titles updated.")




# BELOW is from original ticktick-py script:





# # Initialize the OAuth2 client
# auth_client = OAuth2(client_id=client_id, client_secret=client_secret, redirect_uri=redirect_uri)

# # Initialize the TickTick client with the OAuth2 client
# client = TickTickClient(username='branstrom@gmail.com', password='', oauth=auth_client)

# # Fetch all projects to get the Inbox ID
# projects = client.state['projects']
# inbox_id = client.inbox_id

# # Fetch all tasks from Inbox
# tasks = client.state['tasks']
# inbox_tasks = tasks # [task for task in tasks if task['projectId'] == inbox_id]

# # Function to clean task titles
# def clean_title(title):
#     # Remove empty brackets at the start
#     cleaned_title = re.sub(r'^\[\s*\]', '', title)
#     # Remove dates in the format YYYY-MM-DD
#     cleaned_title = re.sub(r'\d{4}-\d{2}-\d{2}', '', cleaned_title)
#     # Remove any leading/trailing spaces
#     cleaned_title = cleaned_title.strip()
#     return cleaned_title

# # Update task titles
# for task in inbox_tasks:
#     task_id = task['id']
#     original_title = task['title']
#     new_title = clean_title(original_title)
    
#     if original_title != new_title:
#         task['title'] = new_title
#         client.task.update(task)
#         print(f"Updated task {task_id}: {original_title} -> {new_title}")

# print("Task titles updated.")
