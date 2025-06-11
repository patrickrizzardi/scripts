import folderSize from 'get-folder-size';

export const getFolderSize = async (path: string): Promise<number> => {
  return await folderSize.loose(path);
};
