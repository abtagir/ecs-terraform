🗳️ Vote App on AWS ECS – Infrastructure-as-Code (Terraform)

This project deploys a fully working Vote App on AWS ECS Fargate, consisting of:
- vote-client — Node.js frontend
- vote-server — Python Flask backend
- redis — in-memory datastore
- Application Load Balancer — exposes the UI and API
- ECS Service Connect — internal service-to-service communication
- Autoscaling — client service CPU-based scaling
- ECS Exec — remote shell into Fargate containers
- CloudWatch logs — backend logging pipeline

All infrastructure is defined using Terraform.
________________________________________________________________________________
<img width="633" height="273" alt="image" src="https://github.com/user-attachments/assets/5a226235-29e2-48ea-ada8-e84b54e2d9db" />

________________________________________________________________________________

<img width="468" height="478" alt="image" src="https://github.com/user-attachments/assets/a5a8820f-e3fb-4676-a8f2-1b31cbdfb368" />

All tasks run in private subnets; only ALB is public.


Additionally:
- NAT Gateway allows tasks to reach the internet (e.g., pulling images)
- Security groups restrict access between services
- Autoscaling adjusts number of client tasks
- CloudWatch logs retain backend logs
- ECS Exec enables remote access into running Fargate tasks
________________________________________________________________________________
🧩 Component Responsibilities
vote-client
- Serves the UI (index.html)
- Sends votes via POST /api/vote
- Fetches results from GET /api/results
- Receives VOTE_SERVER_URL from ECS Task Definition:
   http://vote-server.vote.local:5000
- Communicates privately through ECS Service Connect

vote-server
- Flask backend
- Exposes /vote and /results
- Stores votes in Redis
- Reads environment variables:
   REDIS_HOST=redis.vote.local
   REDIS_PORT=6379

Redis
- Stores counters for dogs and cats
- Only accessible inside private VPC + Service Connect mesh
________________________________________________________________________________
⚙️ Infrastructure Features
| Component           | Description                                      |
| ------------------- | ------------------------------------------------ |
| **ECS Fargate**     | Fully serverless container runtime               |
| **Service Connect** | Mesh-style, DNS-based internal service discovery |
| **ALB**             | Entry point for frontend and API                 |
| **CloudWatch Logs** | `/ecs/vote-server`                               |
| **IAM Roles**       | ECS task execution + SSM ECS Exec                |
| **Autoscaling**     | CPU based scaling on vote-client tasks           |
| **Private Subnets** | All ECS tasks run without public IPs             |
| **NAT Gateway**     | Allows tasks to pull container images            |
________________________________________________________________________________
🚀 Deployment Instructions

1️⃣ Clone the repository
   git clone https://github.com/<your-repo>/vote-app-ecs.git
   cd vote-app-ecs
   
2️⃣ Configure AWS credentials
   aws configure
   
3️⃣ Initialize Terraform
   terraform init
   
4️⃣ Review the plan
   terraform plan
   
5️⃣ Deploy everything
   terraform apply
   
Deployment usually takes 5–7 minutes because of ECS + ALB provisioning.
________________________________________________________________________________
🌐 Accessing the Application

After deployment, Terraform outputs the ALB DNS name:

   vote_alb_dns = http://vote-alb-12345.eu-central-1.elb.amazonaws.com

Open it in your browser:

   👉 http://vote-alb-xxxx.eu-central-1.elb.amazonaws.com

You will see:
- The voting UI
- Buttons to vote for cats or dogs
- Live results
________________________________________________________________________________
🔧 ECS Exec (Debugging Running Tasks)

To enter the vote-server task:

aws ecs execute-command \
  --cluster vote-cluster \
  --task <task-id> \
  --container vote-server \
  --interactive \
  --command "/bin/sh"

Check environment variables:
   printenv | grep REDIS

Test Redis manually:

python3 - << 'EOF'
import redis, os
r = redis.StrictRedis(
    host=os.getenv("REDIS_HOST"),
    port=int(os.getenv("REDIS_PORT")),
    db=0
)
print("Ping:", r.ping())
print("dogs:", r.get("dogs"))
print("cats:", r.get("cats"))
EOF
________________________________________________________________________________
🔗 How Services Communicate (Detailed Flow)
Client → Server

Frontend sends:

   POST /api/vote
   GET  /api/results

ALB listener rule:

   /api/*  → vote-server target group (port 5000)

Server → Redis

vote-server uses Service Connect DNS:

   redis.vote.local:6379

Service Connect routes traffic inside the mesh to the redis task.

Client → Server (internal, not used through browser)

Even though this app uses ALB for client→server calls,
the backend DNS is also available through Service Connect:

   vote-server.vote.local:5000
   
This is useful if the frontend ever becomes private-only.
________________________________________________________________________________
📊 Autoscaling
vote-client service auto-scales between 1–4 tasks based on CPU:
- Scale up above 70%
- Scale down below 30%

Configured using:
- CloudWatch alarms
- Application Auto Scaling
________________________________________________________________________________
👤 Author

Tagir Abdulkhaev
Infrastructure-as-Code | AWS | Containers | Terraform
