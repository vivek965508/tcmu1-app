# ==============================================================================
# TCMU-1 UNIVERSAL GSM MOTOR CONTROLLER - PYTHON SIMULATOR FOR VS CODE
# Run in VS Code terminal: python3 tcmu1_simulator.py
# ==============================================================================
import re

def parse_tcmu1_users(sms_text: str):
    """Parses exact reply format:
    *TCMU-1 USERS*
    USER1 = 8081728811,
    USER2 = 7839455008,
    USER4 = 9236504217.
    """
    users = {1: "", 2: "", 3: "", 4: ""}
    for i in range(1, 5):
        match = re.search(rf"USER\s*{i}\s*=\s*(\d{{10,12}})", sms_text, re.IGNORECASE)
        if match:
            users[i] = match.group(1)
    return users

if __name__ == "__main__":
    sample_reply = """*TCMU-1 USERS*
USER1 = 8081728811,
USER2 = 7839455008,
USER4 = 9236504217."""
    parsed = parse_tcmu1_users(sample_reply)
    print("Parsed TCMU-1 Users:", parsed)
