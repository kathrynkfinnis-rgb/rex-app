import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.kathrynfinnis.rexapp',
  appName: 'Rex',
  webDir: '.output/public',
  server: {
    url: 'https://kathrynkfinnis-rgb-rex-app.kathryn-k-finnis.workers.dev',
    cleartext: false
  }
};

export default config;
