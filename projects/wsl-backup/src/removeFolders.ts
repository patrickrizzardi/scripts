import { readdirSync, statSync, rmdirSync } from 'fs';
import { join } from 'path';
import 'colors';
import { getFolderSize } from './utils/getFolderSize';
import { folderIsDirectory } from './utils/checkIfFolderIsDirectory';
import { convertToReadableSize } from './utils/convertSizeToReadableSize';

/**
 * Remove all folders from the specified directory that match the folderNameToRemove.
 * @param startDir The directory to start the search from.
 * @param folderNameToRemove The folder name to remove.
 * Example: removeNodeModules(join(__dirname, 'test'), 'node_modules');
 */
export const removeFolders = async (startDir: string, folderNameToRemove: string) => {
  try {
    console.log(`Removing ${folderNameToRemove} from:`.cyan, startDir);
    const startDirSize = await getFolderSize(startDir);

    const deleteFolders = (currentDir: string) => {
      const folders = readdirSync(currentDir);
      console.log('Checking:', currentDir);

      for (const folder of folders) {
        const path = join(currentDir, folder); // Build the full path

        if (folderIsDirectory(path)) {
          if (folder === folderNameToRemove && startDir !== join(currentDir, folderNameToRemove)) {
            console.log(`Deleting: ${path}`.red);
            rmdirSync(path, { recursive: true });
          } else {
            // Recursively call the function for the sub-directory
            deleteFolders(path);
          }
        }
      }
    };

    deleteFolders(startDir);

    const endDirSize = await getFolderSize(startDir);
    const savedSize = convertToReadableSize(startDirSize - endDirSize);

    console.log('Start size:', convertToReadableSize(startDirSize).yellow);
    console.log('End size:', convertToReadableSize(endDirSize).yellow);
    console.log('You saved:', savedSize.green);
  } catch (error: any) {
    if (error.code === 'EACCES' || error.code === 'EPERM') {
      return console.log(
        'Permission denied. Ensure you have the necessary permissions to delete all node_modules folders.'.red,
      );
    }

    console.log('An error occurred:', error);
  }
};
