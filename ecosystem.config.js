module.exports = {
  apps: [{
    name: "signconnect",
    script: "server.js",
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: "256M",
    env: {
      NODE_ENV: "production",
      PORT: 8080,
      METERED_API_KEY: "",
      METERED_API_URL: "https://aiml_project.metered.live/api/v1/turn/credentials"
    }
  }]
};
