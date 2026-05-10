import base64
import urllib.request
import os

graph = """erDiagram
    Automation {
        uuid Id PK
        string Name
        boolean IsActive
        string TriggerType
        jsonb TriggerConfig
        string ActionType
        jsonb ActionConfig
        datetime CreatedAt
    }
    
    ExecutionLog {
        uuid Id PK
        uuid AutomationId FK
        string Status
        string Message
        datetime ExecutedAt
    }

    Automation ||--o{ ExecutionLog : has_many
"""

b64 = base64.b64encode(graph.encode('utf-8')).decode('utf-8')
url = f"https://mermaid.ink/img/{b64}"

try:
    print(f"Downloading from {url}")
    req = urllib.request.Request(
        url, 
        data=None, 
        headers={
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
        }
    )
    with urllib.request.urlopen(req) as response:
        with open(r"c:\Users\User-Pc\OneDrive\Desktop\automateIt\Database_ERD.png", "wb") as f:
            f.write(response.read())
    print("Downloaded Database_ERD.png successfully.")
except Exception as e:
    print(f"Error: {e}")
