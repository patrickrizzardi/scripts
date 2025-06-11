const fs = require('fs')
const path = require('path')

// read the folder names in the current directory
const folders = fs.readdirSync(__dirname)

let files = []
for(const folder of folders) {
    // read the file names in each folder
    const folderPath = path.join(__dirname, folder)

    // enure that the path is a directory
    if (!fs.lstatSync(folderPath).isDirectory()) continue
    
    const envPaths = recursiveReadDir(folderPath, [], [])

    if(envPaths.length > 0) files.push(...envPaths)
}

function recursiveReadDir  (folderPath, dirs, envPaths)  {    
    let contentOfFolder = fs.readdirSync(folderPath)

    for(const content of contentOfFolder) {
        // If the content a directory add it to the dirs array
        if (fs.lstatSync(path.join(folderPath, content)).isDirectory()) dirs.push(content)        

        // If the file is a .env file add it to the envPaths array
        if (content === '.env') envPaths.push(path.join(folderPath, content))        
    }

    // If there are directories in the dirs array, recursively call the function
    if (dirs.length > 0) {
        for(const dir of dirs) {
            const dirPath = path.join(folderPath, dir)
            recursiveReadDir(dirPath, [], envPaths)
        }
    }

    return envPaths
}

if(files.length > 0) {
    for(const file of files) {
        // Get the folder name of the file
        const folderName = file.split('/.env')[0].split('/').pop()
        const filePath = path.join(__dirname, `env/${folderName}.env`)
        fs.copyFileSync(file, filePath)
    }
}