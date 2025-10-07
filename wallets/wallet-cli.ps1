import json
import os
import sys
import requests

# === Basic Wallet Info ===
WALLET_FILE = "wallet.json"
NODE_URL = "http://127.0.0.1:5000"

# === Helper Functions ===
def load_wallet():
    if not os.path.exists(WALLET_FILE):
        return {"address": None, "balance": 0, "tokens": {}}
    with open(WALLET_FILE, "r") as f:
        return json.load(f)

def save_wallet(wallet):
    with open(WALLET_FILE, "w") as f:
        json.dump(wallet, f, indent=4)

# === Commands ===
def create_wallet():
    wallet = {
        "address": os.urandom(8).hex(),
        "balance": 100,
        "tokens": {}
    }
    save_wallet(wallet)
    print(f"✅ Wallet created! Address: {wallet['address']} with balance 100 EAGL")

def show_balance():
    wallet = load_wallet()
    print(f"💰 Balance: {wallet['balance']} EAGL")
    if wallet["tokens"]:
        print("🔹 Tokens:")
        for token, amt in wallet["tokens"].items():
            print(f"   - {token}: {amt}")

def send_tokens():
    wallet = load_wallet()
    if not wallet["address"]:
        print("⚠️ No wallet found! Run 'create' first.")
        return

    recipient = input("Recipient address: ").strip()
    token = input("Token name (e.g., EAGL): ").strip().upper()
    amount = float(input("Amount to send: "))

    tx_data = {
        "sender": wallet["address"],
        "recipient": recipient,
        "token": token,
        "amount": amount
    }

    try:
        r = requests.post(f"{NODE_URL}/send", json=tx_data)
        if r.status_code == 200:
            print(f"✅ Sent {amount} {token} to {recipient}!")
        else:
            print(f"❌ Error: {r.text}")
    except Exception as e:
        print(f"🚫 Could not connect to node: {e}")

def update_from_node():
    wallet = load_wallet()
    try:
        r = requests.get(f"{NODE_URL}/wallet/{wallet['address']}")
        if r.status_code == 200:
            data = r.json()
            wallet["balance"] = data.get("balance", wallet["balance"])
            wallet["tokens"] = data.get("tokens", wallet["tokens"])
            save_wallet(wallet)
            print("🔄 Wallet synced with blockchain.")
        else:
            print(f"❌ Node returned error: {r.text}")
    except Exception as e:
        print(f"🚫 Could not connect to node: {e}")

def show_help():
    print("""
Available commands:
  create    - Create a new wallet
  balance   - Show wallet balance and tokens
  send      - Send tokens to another address
  sync      - Update wallet from node
  quit      - Exit CLI
""")

# === Main Loop ===
def main():
    print("🦅 Welcome to the EAGL Wallet CLI")
    print("Type 'help' for commands.")

    while True:
        cmd = input("> ").strip().lower()
        if cmd == "create":
            create_wallet()
        elif cmd == "balance":
            show_balance()
        elif cmd == "send":
            send_tokens()
        elif cmd == "sync":
            update_from_node()
        elif cmd == "help":
            show_help()
        elif cmd in ["quit", "exit"]:
            print("👋 Goodbye!")
            sys.exit(0)
        else:
            print("❓ Unknown command. Type 'help'.")

if __name__ == "__main__":
    main()
