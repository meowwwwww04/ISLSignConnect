# SignConnect — Cloud Deployment Guide (Oracle Cloud Free Tier)

## Step 1: Create Oracle Cloud Account

1. Go to https://cloud.oracle.com/free
2. Click "Start for free"
3. Sign up (credit card required only for verification, you won't be charged on always-free tier)
4. Verify your email and complete registration

## Step 2: Create a Free VM Instance

1. After logging in, click the hamburger menu (☰) → **Compute** → **Instances**
2. Click **"Create Instance"**
3. Fill in:
   - **Name:** `signconnect-server`
   - **Image:** Ubuntu 22.04 (or Ubuntu 20.04)
   - **Shape:** Select **VM.Standard.A1.Flex** (Always Free eligible — ARM-based)
     - If A1.Flex is not available, use **VM.Standard.E2.1.Micro** (also always free)
   - **Boot volume:** 50 GB (default is fine)
4. Under **Networking:**
   - Select **"Assign a public IP address"** ✅
5. Under **Add SSH keys:**
   - Click **"Generate a key pair"**
   - Download both the **private key** and **public key**
   - Save them safely — you need the private key to connect
6. Click **Create**
7. Wait 2-3 minutes for the instance to become "Running"

## Step 3: Open Firewall Ports

1. In the left menu → **Networking** → **Virtual Cloud Networks**
2. Click on your VCN (it was auto-created with the instance)
3. Click on the **Subnet** link
4. Click on the **Security List** (the default one)
5. Click **"Add Ingress Rules"**
6. Add these two rules:

   **Rule 1 — HTTP:**
   - Source CIDR: `0.0.0.0/0`
   - Destination Port Range: `8080`
   - Description: `SignConnect HTTP`

   **Rule 2 — SSH:**
   - Source CIDR: `0.0.0.0/0`
   - Destination Port Range: `22`
   - Description: `SSH Access`

7. Click **"Add Ingress Rules"** to save

## Step 4: Connect to Your VM

Open a terminal on your laptop and run:

```bash
chmod 400 ~/Downloads/signconnect-ssh-key.key
ssh -i ~/Downloads/signconnect-ssh-key.key ubuntu@<YOUR_VM_PUBLIC_IP>
```

Replace `<YOUR_VM_PUBLIC_IP>` with the public IP shown on your instance details page.

## Step 5: Upload the Project

From your laptop (in a NEW terminal window, not the SSH session):

```bash
# Go to the project directory
cd /home/yume26/Desktop/islProject

# Create a tar file for upload (excluding node_modules, .git, etc.)
tar czf /tmp/signconnect.tar.gz \
  --exclude='node_modules' \
  --exclude='.git' \
  --exclude='.venv' \
  --exclude='*.pem' \
  --exclude='signconnect_app/.dart_tool' \
  --exclude='signconnect_app/build' \
  --exclude='signconnect_app/.gradle' \
  --exclude='signconnect_app/android' \
  --exclude='signconnect_app/ios' \
  --exclude='signconnect_app/linux' \
  --exclude='signconnect_app/macos' \
  --exclude='signconnect_app/windows' \
  --exclude='signconnect_app/test' \
  .

# Upload to the VM (replace with your actual IP and key path)
scp -i ~/Downloads/signconnect-ssh-key.key /tmp/signconnect.tar.gz ubuntu@<YOUR_VM_PUBLIC_IP>:~/
```

## Step 6: Deploy on the VM

Go back to your SSH terminal and run:

```bash
# Extract the project
mkdir -p ~/signconnect
tar xzf ~/signconnect.tar.gz -C ~/signconnect

# Run the deployment script
cd ~/signconnect
chmod +x deploy.sh
./deploy.sh
```

The script will:
- Install Node.js
- Install PM2 (process manager that keeps the server running)
- Install project dependencies
- Start the server
- Open firewall ports

## Step 7: Access Your App

Once deployment finishes, you'll see output like:

```
Your app is now running at:
http://<YOUR_VM_PUBLIC_IP>:8080
```

**Share this URL with anyone, anywhere in the world!**

Both users open this URL, enter the same room code, and connect.

## Managing the Server

### Check if server is running:
```bash
pm2 status
```

### View server logs:
```bash
pm2 logs signconnect
```

### Restart the server:
```bash
pm2 restart signconnect
```

### Stop the server:
```bash
pm2 stop signconnect
```

## Updating the App

When you make changes to the code:

1. From your laptop, re-create the tar file:
```bash
cd /home/yume26/Desktop/islProject
tar czf /tmp/signconnect.tar.gz --exclude='node_modules' --exclude='.git' .
```

2. Upload it:
```bash
scp -i ~/Downloads/signconnect-ssh-key.key /tmp/signconnect.tar.gz ubuntu@<YOUR_VM_PUBLIC_IP>:~/
```

3. SSH into the VM and deploy:
```bash
ssh -i ~/Downloads/signconnect-ssh-key.key ubuntu@<YOUR_VM_PUBLIC_IP>
cd ~/signconnect
tar xzf ~/signconnect.tar.gz -C . --overwrite
npm install --production
pm2 restart signconnect
```

## Costs

**Oracle Cloud Always Free Tier includes:**
- 2 AMD Compute VMs (1/8 OCPU each, 1 GB RAM each)
- OR 4 ARM Ampere A1 cores (24 GB RAM total) — always free
- 200 GB block storage
- 10 GB object storage
- 5 GB archive storage
- 10 TB/month data transfer

**You will NOT be charged** as long as you stay within the always-free limits. A SignConnect server uses minimal resources.

## Troubleshooting

### "Connection refused" error
- Make sure port 8080 is open in the security list
- Check if the server is running: `pm2 status`

### Can't SSH into the VM
- Make sure you're using the correct private key
- Make sure the instance status is "Running"
- Check the public IP is correct

### Server crashes
- Check logs: `pm2 logs signconnect`
- Restart: `pm2 restart signconnect`

### Camera not working (HTTP)
- Mobile browsers require HTTPS for camera access
- On Oracle Cloud, you can set up Nginx + Let's Encrypt for free HTTPS
- Or access via `https://` using a self-signed certificate (browser will warn but camera works)
