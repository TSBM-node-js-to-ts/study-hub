FROM node:20-bookworm
RUN apt-get update && apt-get install -y hyperfine && rm -rf /var/lib/apt/lists/*
RUN corepack enable
WORKDIR /workspace
COPY setup-and-bench.sh ./
RUN chmod +x setup-and-bench.sh
CMD ["bash", "-lc", "./setup-and-bench.sh"]
