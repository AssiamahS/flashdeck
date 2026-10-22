#!/usr/bin/env python3
"""Ivy's Security+ simulations (security-plus-sims image cards + the 4 sims at the
top of Security_Plus_501.pdf) as tap-able practice-test questions: one lettered
question per drag-and-drop slot / hotspot row. Writes deck `security-plus-sims-quiz`
into decks.json (replaces it if present)."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
L = "ABCDEFGH"

def q(sim, prompt, options, *answers):
    front = f"[{sim}] {prompt}\n" + "\n".join(f"{L[i]}. {o}" for i, o in enumerate(options))
    back = "\n".join(f"{L[options.index(a)]}. {a}" for a in answers)
    return {"front": front, "back": back}

cards = []

# Ivy 501 PDF sim 1 — file integrity monitoring (key as marked in her PDF)
cards.append(q("Sim: FIM log", "File integrity monitoring on a busy server that has never been updated since install. Which log entry is the FIRST instance of compromise?\n/etc/passwd hashes change at 1/1/2017 1:20, 1:22, 1:23, 1:23\n/etc/iptables/iptables-save: 12/30 1:00 ...cc3, 12/31 2:00 ...co3, 1/1 3:00 ...co3\n/boot/initrd.img: 12/30 and 12/31 ...ca02, 1/1/2017 3:30 7813a8...",
    ["/etc/passwd 1/1/2017 1:20:34", "/etc/iptables/iptables-save 12/30/2016 1:00:00", "/etc/iptables/iptables-save 12/31/2016 2:00:00", "/boot/initrd.img 1/1/2017 3:30:00"],
    "/etc/iptables/iptables-save 12/30/2016 1:00:00"))

# Smartphone vs terminal server controls (sim 1 of the dump + Ivy 501 sim 2)
phone = ["Screen Lock", "Strong Password", "Device Encryption", "Remote Wipe", "GPS Tracking", "Pop-up blocker"]
server = ["Cable Locks", "Antivirus", "Host Based Firewall", "Proximity Reader", "Sniffer", "Mantrap"]
for c in phone + server:
    cards.append(q("Sim: Device controls", f"Drag and drop: where does the control \"{c}\" go?",
        ["Company Managed Smart Phone", "Data Center Terminal Server"],
        "Company Managed Smart Phone" if c in phone else "Data Center Terminal Server"))

# Attack types (dump sim 2 + Ivy 501 sim 4)
atk = ["Whaling", "Hoax", "Vishing", "Spam", "Pharming", "Spim", "Phishing", "Spear phishing"]
for vector, ans in [
    ("Attacker gains confidential company information; target = CEO and board members", "Whaling"),
    ("Attacker posts a link to fake AV software on multiple social networks; target = broad set of victims", "Hoax"),
    ("Attacker collecting credit card details; target = phone-based victim", "Vishing"),
    ("Attacker mass-mails product information to parties that already opted out of advertisements", "Spam"),
    ("Attacker redirects name resolution entries from the legitimate site to a fraudulent site", "Pharming"),
]:
    cards.append(q("Sim: Attacks", f"Hotspot: identify the attack. {vector}.", atk, ans))

# Floor plan (dump sim 3 + Ivy 501 sim 3)
fp = ["Cable Locks", "Proximity Badge + Safe", "CCTV, Proximity Badge, Mantrap, Locking Cabinets, Biometric Reader", "Biometric Reader"]
for spot, ans in [
    ("Unsupervised lab laptops (6 of them)", "Cable Locks"),
    ("The Office (workstation, laptop, key box)", "Proximity Badge + Safe"),
    ("The Data Center (servers)", "CCTV, Proximity Badge, Mantrap, Locking Cabinets, Biometric Reader"),
    ("Employee laptops on wireless (3 of them)", "Biometric Reader"),
]:
    cards.append(q("Sim: Floor plan", f"Floor plan drag and drop (all objects used: locking cabinets 1, safe 1, CCTV 1, mantrap 1, biometric reader 4, proximity badge 2, cable locks 6). What goes on: {spot}?", fp, ans))

# RAID (dump sim 168)
raid = ["RAID-0 (striping)", "RAID-1 (mirroring)", "RAID-5 (striping + 1 parity)", "RAID-6 (striping + 2 parity)"]
for srv, ans in [("Media Streaming Server", "RAID-0 (striping)"), ("Authentication Server", "RAID-1 (mirroring)"),
                 ("Email Archive", "RAID-5 (striping + 1 parity)"), ("Identity Management Server", "RAID-6 (striping + 2 parity)")]:
    cards.append(q("Sim: RAID", f"Drag and drop: which RAID level matches the {srv} profile?", raid, ans))
cards.append(q("Sim: RAID", "RAID-5 on 4 disks: how is it built?",
    ["3 stripe data + 1 parity box checked", "2 mirror data, no parity", "4 stripe data + 2 parity boxes checked", "2 stripe data, no parity"],
    "3 stripe data + 1 parity box checked"))
cards.append(q("Sim: RAID", "RAID-6 on 4 disks: how is it built?",
    ["3 stripe data + 1 parity box checked", "2 mirror data, no parity", "4 stripe data + 2 parity boxes checked", "2 stripe data, no parity"],
    "4 stripe data + 2 parity boxes checked"))

# Ports (dump sim 221)
ports = ["21", "22", "23", "25", "69", "161"]
for proto, ans in [("FTP", "21"), ("Telnet", "23"), ("SMTP", "25"), ("SNMP", "161"), ("SCP", "22"), ("TFTP", "69")]:
    cards.append(q("Sim: Ports", f"Drag and drop the default port for {proto}.", ports, ans))

# Order of volatility (dump sim 236)
vol = ["CPU cache", "RAM", "Swap", "Hard drive"]
for n, ans in enumerate(vol, 1):
    cards.append(q("Sim: Order of volatility", f"Order of volatility, most to least volatile: what is #{n}?", vol, ans))

# Social engineering (dump sim 247)
se = ["Phishing", "Whaling", "Vishing", "Spim", "Social Engineering", "Pharming", "Spoofing", "Hoax"]
for scen, ans in [
    ("Email sent to multiple users with a link to verify username/password on an external site", "Phishing"),
    ("Phone calls made to the CEO asking for various financial data", "Whaling"),
    ("Phone call to an individual claiming an IT issue and asking for the user's password", "Vishing"),
    ("Instant message on a social media site from a friend with a link to a breakthrough diet", "Spim"),
    ("A friend/colleague asks personal questions that could be typical password reset questions", "Social Engineering"),
]:
    cards.append(q("Sim: Attack type", f"Choose the attack type: {scen}.", se, ans))

# Room / WiFi controls (dump sim 248)
cards.append(q("Sim: Room controls", "CEO's office: remove redundancies to deploy THREE-factor authentication while keeping the expensive iris scanner. Which set?",
    ["Iris Scanner + Smart Card Reader + Pin Pad", "Iris Scanner + Thumbprint Scanner + Voice Recognition", "Iris Scanner + Username/Password + Pin Pad", "Iris Scanner + Smart Card Reader"],
    "Iris Scanner + Smart Card Reader + Pin Pad"))
cards.append(q("Sim: Room controls", "Data Center: add a \"something you know\" factor and use the existing smart card reader on the door. Which set?",
    ["Smart Card Reader + Pin Pad", "Smart Card Reader + Iris Scanner", "Smart Card Reader only", "Mantrap + Thumbprint Scanner"],
    "Smart Card Reader + Pin Pad"))
cards.append(q("Sim: Room controls", "Help Desk office: single-factor authentication using physical tokens handed to guests by the receptionist. Which control?",
    ["Smart Card Reader", "Pin Pad", "Thumbprint Scanner", "Username/Password"], "Smart Card Reader"))
cards.append(q("Sim: Room controls", "Public Cafe: secure the WAP with WPA and put the passphrase on customer receipts. Which setting?",
    ["WPA with a pre-shared key (PSK)", "WPA Enterprise with RADIUS", "Open network + captive portal", "WEP with a 40-bit key"],
    "WPA with a pre-shared key (PSK)"))

# Firewall rules (dump sim 249)
cards.append(q("Sim: Firewall", "Only allow the Accounting computer (10.4.255.10/24) HTTPS access to Administrative Server 1 (10.4.255.101). Which rule?",
    ["10.4.255.10/24 → 10.4.255.101, 443, TCP, Allow", "10.4.255.10/24 → 10.4.255.101, 80, TCP, Allow", "10.4.255.10/24 → 10.4.255.101, 443, UDP, Allow", "10.4.255.10/24 → 10.4.255.102, Any, Any, Allow"],
    "10.4.255.10/24 → 10.4.255.101, 443, TCP, Allow"))
cards.append(q("Sim: Firewall", "Only allow the HR computer (10.4.255.10/23) to talk to Server 2 (10.4.255.2) over SCP. Which rule?",
    ["10.4.255.10/23 → 10.4.255.2, 22, TCP, Allow", "10.4.255.10/23 → 10.4.255.2, 21, TCP, Allow", "10.4.255.10/23 → 10.4.255.2, 69, UDP, Allow", "10.4.255.10/23 → 10.4.255.2, 443, TCP, Allow"],
    "10.4.255.10/23 → 10.4.255.2, 22, TCP, Allow"))
cards.append(q("Sim: Firewall", "Allow the IT computer (10.4.255.10/25) to reach both Administrative Server 1 (.101) and Administrative Server 2 (.102). Which rules? (Select TWO)",
    ["10.4.255.10/25 → 10.4.255.101, Any, Any, Allow", "10.4.255.10/25 → 10.4.255.102, Any, Any, Allow", "10.4.255.10/25 → 10.4.255.2, 22, TCP, Allow", "10.4.255.10/26 → 10.4.255.101, Any, Any, Allow"],
    "10.4.255.10/25 → 10.4.255.101, Any, Any, Allow", "10.4.255.10/25 → 10.4.255.102, Any, Any, Allow"))

# Authentication categories (dump sim 250)
cat = ["Something you have", "Something you know", "Something you are", "All given authentication categories"]
for item, ans in [("Retina scan", "Something you are"), ("Smart card", "Something you have"), ("Hardware token", "Something you have"),
                  ("Password", "Something you know"), ("PIN number", "Something you know"), ("Fingerprint scan", "Something you are")]:
    cards.append(q("Sim: Auth factors", f"Authentication category for: {item}?", cat, ans))

# Authentication types (dump sim 252)
typ = ["Biometric authentication", "One Time Password", "Multi-factor", "PAP authentication"]
for item, ans in [("Fingerprint scan", "Biometric authentication"), ("Hardware token", "One Time Password"), ("Smart card", "Multi-factor"),
                  ("Password", "PAP authentication"), ("PIN number", "PAP authentication"), ("Retina scan", "Biometric authentication")]:
    cards.append(q("Sim: Auth types", f"Authentication type for: {item}?", typ, ans))

# Forensics diagram (dump sim 253)
cards.append(q("Sim: Forensics", "Logs show an attack completed against one node (web server 10.10.10.10, database server 10.10.10.12, IDS 10.10.10.20, user PC 172.30.0.1). Which node was compromised?",
    ["Database Server", "Web Server", "IDS", "Users PC"], "Database Server"))
cards.append(q("Sim: Forensics", "Critical production network, LEAST disruptive incident response for the compromised database server. Which actions? (Select TWO)",
    ["Capture network traffic", "Chain of custody", "Shut down the server", "Reimage the server", "Disconnect the whole network"],
    "Capture network traffic", "Chain of custody"))

if __name__ == "__main__":
    path = ROOT / "decks.json"
    data = json.loads(path.read_text())
    deck = {"id": "security-plus-sims-quiz", "name": "Security Plus Simulations Practice", "cards": cards}
    data["decks"] = [d for d in data["decks"] if d["id"] != deck["id"]]
    i = next(n for n, d in enumerate(data["decks"]) if d["id"] == "security-plus-sims") + 1
    data["decks"].insert(i, deck)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    print(len(cards), "sim questions")
