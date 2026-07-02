import { statSync } from 'fs';

export const folderIsDirectory = (path: string) => {
  try {
    return statSync(path).isDirectory();
  } catch (error) {
    return false;
  }
};
