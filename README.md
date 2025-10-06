# 🦅 EAGLCOIN Core Node

EAGLCOIN (**$EAGL**) is a GPU-friendly, ASIC-resistant Proof-of-Work cryptocurrency built for fairness and efficiency.  
It is a fork of [Ergo](https://github.com/ergoplatform/ergo), adapted to favor low-power GPUs and provide a transparent, decentralized network.
DISCLAIMER: This is still in beta and serves as a test project for middle school. I am only one person, so don't expect anything professional here.
---

## ⚙️ Overview

- **Algorithm:** Modified Autolykos (ASIC-resistant)
- **Consensus:** Proof-of-Work (GPU-friendly)
- **Genesis Block:** Height 0 (custom EAGL network)
- **Ticker:** `$EAGL`
- **Main Goal:** Accessible mining and secure decentralization for everyday miners.

---

## 🛠️ Build Instructions (disregard as still working out naming conventions, bugs, jdk issues, etc.

```bash
# 1. Install dependencies
sudo apt install openjdk-11-jdk git sbt -y

# 2. Clone repository
git clone https://github.com/Johndoe15you/EAGLCOIN.git
cd EAGLCOIN

# 3. Build node
sbt assembly

# 4. Run node (default config)
java -jar target/scala-2.12/EAGLCOIN.jar --genesis
