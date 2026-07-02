import { join } from 'path';
import { removeFolders } from './removeFolders';
import { backup } from './backup';

(async () => {
  await removeFolders(join('/user/development'), 'dist');
  await removeFolders(join('/user/development'), 'node_modules');
  await removeFolders(join('/user/development/docker-ark-survival/ark-server'), 'ShooterGame');
  await removeFolders(join('/user/development/docker-ark-asa/server'), 'ShooterGame');

  await backup([
    '/user/development',
    '/user/.bashrc',
    '/user/.ssh',
    '/user/neutrino',
    '/user/ark-asa-configs',
    '/user/docs',
  ]);
})();
