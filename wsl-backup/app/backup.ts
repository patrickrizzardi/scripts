import { readdirSync, statSync, rmdirSync, mkdirSync, copyFileSync } from 'fs';
import { join } from 'path';
import 'colors';
import { folderIsDirectory } from './utils/checkIfFolderIsDirectory';

export const backup = async (path: string[]) => {
  try {
    console.log('Backing up:'.cyan, path);
    const skippedFiles: string[] = [];
    const backupPath = join('/backup');

    // Create the backup folder if it doesn't exist
    if (!statSync(backupPath).isDirectory()) {
      console.log('Creating backup folder'.yellow);
      mkdirSync(backupPath);
    }

    // Create a recursive function to copy all files and folders to the backup folder keeping the same folder structure
    const copyFiles = (dir: string) => {
      /**
       * Need to check if the dir is a file. If it is, we need to handle it
       * before we try to read it as a directory. If we don't, we will get an
       * error.
       */
      if (!folderIsDirectory(dir)) {
        console.log('Copying:'.green, dir);

        const backupFilePath = join(backupPath, dir, '../');
        mkdirSync(backupFilePath, { recursive: true });

        const backupFile = join(backupPath, dir);
        return copyFileSync(dir, backupFile);
      }

      const files = readdirSync(dir);

      for (const file of files) {
        const filePath = join(dir, file);

        if (folderIsDirectory(filePath)) {
          copyFiles(filePath);
        } else {
          try {
            console.log('Copying:'.green, filePath);
            const backupFilePath = join(backupPath, filePath, '../');
            mkdirSync(backupFilePath, { recursive: true });

            const backupFile = join(backupFilePath, file);
            copyFileSync(filePath, backupFile);
          } catch (error: any) {
            if (error.code === 'EACCES' || error.code === 'EPERM') {
              console.log(
                'Permission denied. Ensure you have the necessary permissions to the backup folder and the folders you are backing up.'
                  .red,
              );
            }

            skippedFiles.push(filePath);
          }
        }
      }
    };

    for (const p of path) copyFiles(p);

    if (skippedFiles.length) {
      console.log('The following files were skipped:'.red, skippedFiles);
    } else {
      console.log('Backup complete'.green);
    }
  } catch (error: any) {
    if (error.code === 'EACCES' || error.code === 'EPERM') {
      return console.log(
        'Permission denied. Ensure you have the necessary permissions to the backup folder and the folders you are backing up.'
          .red,
      );
    }

    console.log('An error occurred:', error);
  }
};
