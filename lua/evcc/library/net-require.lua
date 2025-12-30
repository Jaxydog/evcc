---Options that may be present when importing a file.
---
---@class evcc.net_require.Options
---
---@field public ignoreHash? boolean Whether to ignore the current file's hash when checking whether to update.
---@field public skipHashing? boolean Whether to skip hashing the downloaded file.
---@field public forceDownload? boolean Whether to re-download the file regardless of whether it already exists.

---Allows `require` calls to fetch files over a network.
---
---@class evcc.net_require.Lib
local module = {}

---Returns the path of the directory that contains all persistent files.
---
---This can be configured via the `evcc.net_require.persistent_dir` settings key.
---If left unconfigured, it will default to `/.evcc/net-require`
---
---@return string path The directory path.
function module.getPersistentDirectoryPath()
    return settings.get('evcc.net_require.persistent_dir', '/.evcc/net-require')
end

---Provides an interface for managing external repository data.
module.repository = {}

---Returns `true` if the given name is considered valid.
---
---@param name string The repository name.
---
---@return boolean valid Whether the name is valid.
function module.repository.validateName(name)
    return type(name) == 'string' and name:match('^[%l][%l%d]-[%l%d]$')
end

---Returns `true` if the given URL is considered valid.
---
---@param url string The repository URL.
---
---@return boolean valid Whether the URL is valid.
function module.repository.validateUrl(url)
    return type(url) == 'string'
end

---Returns the path of the file that retains global repository information.
---
---This can be configured via the `evcc.net_require.repository_file` settings key.
---If left unconfigured, it will default to `<persistent_dir>/repositories.json`
---
---@return string path The file path.
function module.repository.getPersistentFilePath()
    return settings.get('evcc.net_require.repository_file') or
        fs.combine(module.getPersistentDirectoryPath(), 'repositories.json')
end

---Returns the path of the directory that retains downloaded repository files.
---
---This can be configured via the `evcc.net_require.download_dir` settings key.
---If left unconfigured, it will default to `<persistent_dir>/downloads`
---
---@return string path The directory path.
function module.repository.getPersistentFileDir()
    return settings.get('evcc.net_require.download_dir') or
        fs.combine(module.getPersistentDirectoryPath(), 'downloads')
end

---Returns a list of repositories that have been saved locally.
---
---@return table<string, string> repositories The persistent repositories.
function module.repository.loadPersistentData()
    local file = fs.open(module.repository.getPersistentFilePath(), 'r')

    if not file then return {} end

    local fileContents = file.readAll()

    file.close()

    if not fileContents then return {} end

    local repositoryMap = textutils.unserializeJSON(fileContents) or {}

    for repositoryName, repositoryUrl in pairs(repositoryMap) do
        assert(module.repository.validateName(repositoryName), 'Invalid repository name')
        assert(module.repository.validateUrl(repositoryUrl), 'Invalid repository URL')
    end

    return repositoryMap
end

---Saves the given list of repositories locally.
---
---@param repositories table<string, string> The persistent repositories.
function module.repository.savePersistentData(repositories)
    local persistentDirectoryPath = module.getPersistentDirectoryPath()

    if not fs.exists(persistentDirectoryPath) then
        fs.makeDir(persistentDirectoryPath)
    end

    local file = assert(fs.open(module.repository.getPersistentFilePath(), 'w+'))

    file.write(textutils.serializeJSON(repositories))
    file.close()
end

---Adds the given repository to the local list.
---
---@param name string The repository name.
---@param url string The repository URL.
function module.repository.add(name, url)
    assert(module.repository.validateName(name), 'Invalid repository name')
    assert(module.repository.validateUrl(url), 'Invalid repository URL')

    local repositories = module.repository.loadPersistentData()

    assert(not repositories[name], 'The given repository name already exists')
    assert(http.checkURL(url))

    repositories[name] = url:match('^(.-)/*$')

    module.repository.savePersistentData(repositories)
end

---Returns `true` if the given repository has been registered locally.
---
---@param name string The repository name.
---
---@return boolean exists Whether the repository exists.
function module.repository.has(name)
    assert(module.repository.validateName(name), 'Invalid repository name')

    local repositories = module.repository.loadPersistentData()

    return repositories[name] ~= nil
end

---Returns the URL for the given repository.
---
---@param name string The repository name.
---
---@return string url The repository URL.
function module.repository.getUrl(name)
    assert(module.repository.validateName(name), 'Invalid repository name')

    local repositories = module.repository.loadPersistentData()

    return assert(repositories[name], 'The given repository name does not exist')
end

---Returns the directory that stores downloads for the given repository.
---
---@param name string The repository name.
---
---@return string path The download directory.
function module.repository.getDirPath(name)
    assert(module.repository.validateName(name), 'Invalid repository name')

    local repositories = module.repository.loadPersistentData()

    assert(repositories[name], 'The given repository name does not exist')

    return fs.combine(module.repository.getPersistentFileDir(), name)
end

---Removes the given repository from the local list.
---
---@param name string The repository name.
function module.repository.remove(name)
    assert(module.repository.validateName(name), 'Invalid repository name')

    local repositories = module.repository.loadPersistentData()

    assert(repositories[name], 'The given repository name does not exist')

    repositories[name] = nil

    module.repository.savePersistentData(repositories)
end

---Provides an interface for managing file hashes.
module.hash = {}

---Returns the path of the file that retains download hashes.
---
---This can be configured via the `evcc.net_require.hash_file` settings key.
---If left unconfigured, it will default to `<persistent_dir>/hashes.json`
---
---@return string path The file path.
function module.hash.getPersistentFilePath()
    return settings.get('evcc.net_require.hash_file') or
        fs.combine(module.getPersistentDirectoryPath(), 'hashes.json')
end

---Returns a list of hashes that have been saved locally.
---
---@return table<string, integer> hashes The persistent hashes.
function module.hash.loadPersistentData()
    local file = fs.open(module.hash.getPersistentFilePath(), 'r')

    if not file then return {} end

    local fileContents = file.readAll()

    file.close()

    if not fileContents then return {} end

    local hashesMap = textutils.unserializeJSON(fileContents) or {}

    for filePath, fileHash in pairs(hashesMap) do
        assert(type(filePath) == 'string', 'Invalid file path')
        assert(type(fileHash) == 'number' and math.type(fileHash) == 'integer', 'Invalid file hash')
    end

    return hashesMap
end

---Saves the given list of hashes locally.
---
---@param hashes table<string, integer> The persistent hashes.
function module.hash.savePersistentData(hashes)
    local persistentDirectoryPath = module.getPersistentDirectoryPath()

    if not fs.exists(persistentDirectoryPath) then
        fs.makeDir(persistentDirectoryPath)
    end

    local file = assert(fs.open(module.hash.getPersistentFilePath(), 'w+'))

    file.write(textutils.serializeJSON(hashes))
    file.close()
end

---Returns the hash for the current string.
---
---This function implements the `djb2` hash algorithm.
---
---This is *NOT* cryptographically sound! Do not use this for anything important!
---
---@param text string The text to hash.
---
---@return integer hash The 32-bit hash.
function module.hash.generate(text)
    local hash = 5381

    for character in text:gmatch('.') do
        hash = math.fmod((hash * 33) + string.byte(character), 2147483648)
    end

    return hash
end

---Adds a hash to the persistent cache.
---
---@param path string The file path.
---@param hash integer The file hash.
function module.hash.add(path, hash)
    assert(type(path) == 'string', 'Invalid file path')

    local hashes = module.hash.loadPersistentData()

    hashes[path] = hash

    module.hash.savePersistentData(hashes)
end

---Returns `true` if the given path has a cached hash.
---
---@param path string The file path.
---
---@return boolean exists Whether the hash is saved.
function module.hash.has(path)
    assert(type(path) == 'string', 'Invalid file path')

    local hashes = module.hash.loadPersistentData()

    return hashes[path] ~= nil
end

---Returns the cached hash for the given path.
---
---@param path string The file path.
---
---@return integer | nil hash The hash.
function module.hash.get(path)
    assert(type(path) == 'string', 'Invalid file path')

    local hashes = module.hash.loadPersistentData()

    return hashes[path]
end

---Removes a hash to the persistent cache.
---
---@param path string The file path.
function module.hash.remove(path)
    assert(type(path) == 'string', 'Invalid file path')

    local hashes = module.hash.loadPersistentData()

    hashes[path] = nil

    module.hash.savePersistentData(hashes)
end

---Imports the specified library.
---
---The provided string should be of the form `repository>path/to/file`.
---
---@param import string The import string.
---@param options? evcc.net_require.Options Import options.
---
---@return unknown module The imported module.
function module.require(import, options)
    options = options or {}

    local repositoryName, externalFileName = import:match('^(.-)>(.-)$')

    local repositoryUrl = module.repository.getUrl(repositoryName)
    local repositoryPath = module.repository.getDirPath(repositoryName)

    local downloadUrl = repositoryUrl .. '/' .. externalFileName .. '.lua'
    local downloadPath = fs.combine(repositoryPath, externalFileName)

    local shouldOverwriteLocal = options.forceDownload or not fs.exists(downloadPath)
    local downloadContent = nil
    local downloadHash = nil

    if not shouldOverwriteLocal and not options.ignoreHash then
        local currentHash = module.hash.get(downloadPath)

        if currentHash == nil then
            shouldOverwriteLocal = true
        else
            downloadContent = assert(http.get(downloadUrl, {}, false)).readAll() or ''
            downloadHash = module.hash.generate(downloadContent)

            if currentHash ~= downloadHash then
                shouldOverwriteLocal = true
            end
        end
    end

    if shouldOverwriteLocal then
        if not downloadContent then
            downloadContent = assert(http.get(downloadUrl, {}, false)).readAll() or ''

            if not options.skipHashing then
                module.hash.add(downloadPath, module.hash.generate(downloadContent))
            end
        end

        local parentDirPath = fs.getDir(downloadPath)

        if not fs.exists(parentDirPath) then
            fs.makeDir(parentDirPath)
        end

        local file = assert(fs.open(downloadPath, 'w+'))

        file.write(downloadContent)
        file.close()
    end

    if package.path:find(repositoryPath, 1, true) == nil then
        package.path = ('%s;%s/?.lua'):format(package.path, repositoryPath)
    end

    return require(externalFileName)
end

return setmetatable(module, {
    __call = function(this, ...)
        return this.require(...)
    end
})
