local success, message = pcall(function()
    local repositoryUrl = 'https://raw.githubusercontent.com/Jaxydog/evcc/refs/heads/main/lua'

    assert(http.checkURL(repositoryUrl))

    local downloadContent = assert(http.get(repositoryUrl .. '/evcc/library/net-require.lua', {}, false)).readAll()

    assert(downloadContent, 'An empty file was downloaded, something seems wrong!')

    local downloadFilePath = settings.get('evcc.net_require.install_path') or
        fs.combine(settings.get('evcc.net_require.persistent_dir', '/.evcc/net-require'), 'net-require.lua')

    local downloadDirPath = fs.getDir(downloadFilePath)

    if not fs.exists(downloadDirPath) then
        fs.makeDir(downloadDirPath)
    end

    local file = assert(fs.open(downloadFilePath, 'w+'))

    file.write(downloadContent)
    file.close()

    package.path = package.path .. ';' .. downloadDirPath .. '/?.lua'

    ---@type evcc.net_require.Lib
    local netRequire = require('net-require')

    if not netRequire.repository.has('evcc') then
        netRequire.repository.add('evcc', repositoryUrl .. '/evcc/library')
    end
    if not netRequire.repository.has('evcc-programs') then
        netRequire.repository.add('evcc-programs', repositoryUrl .. '/evcc/program')
    end
end)

if not success then
    printError('Unable to install `net-require`!')
    printError('Reason: ' .. (message or 'N/A'))

    return 1
end
