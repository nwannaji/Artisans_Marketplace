import requests
from django.conf import settings

def send_sms(phone_number, message):
    url = 'https://api.ebulksms.com:443/sendsms'
    payload = {
        'username': settings.EBULKSMS_USERNAME,
        'apikey': settings.EBULKSMS_API_KEY,
        'sender': settings.EBULKSMS_SENDER_NAME,
        'messagetext': message,
        'flash': 0,
        'recipients': [phone_number],
    }

    try:
        response = requests.post(url, json=payload, timeout=10)
        result = response.json()
        
        if result.get('response_code') == 'SUCCESS':
            return True
        else:
            print(f"SMS sending failed: {result.get('response_message')}")
            return False
    except Exception as e:
        print(f"SMS sending error: {e}")
        return False
