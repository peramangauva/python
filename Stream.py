import requests, os, time

URL = "http://127.0.0.1:5000/emojis"
SCALE = 150

while True:
    try:
        r = requests.post(URL, json={"scale": SCALE})
        if r.status_code == 200:
            text = r.json().get("text", "")
            
            # Clear screen and print
            os.system('cls')
            print(text)
            
        time.sleep(0.01) # Small delay to not crash the terminal
    except Exception as e:
        print("Error:", e)
        time.sleep(1)