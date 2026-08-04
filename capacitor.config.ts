import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.kathrynfinnis.rexapp',
  appName: 'Rex',
  webDir: '.output/public',
  server: {
    url: 'https://rex-app.lovable.app',
    cleartext: false
  }
};

export default config;
