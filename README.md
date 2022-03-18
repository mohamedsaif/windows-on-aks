# Windows on AKS
Demonstrating various capabilities about running Windows Containers on AKS

# List of Images

So main windows container base images will be pulled from [Microsoft Container Registry](https://github.com/microsoft/containerregistry).

Looking at the [catalog of MCR](https://mcr.microsoft.com/v2/_catalog), I found the following relevant images:

```json
{ [
    "windows/servercore/iis",
    "windows/servercore/iis/insider",
    "windows",
    "windows/insider",
    "windows/iotcore",
    "windows/iotcore/insider",
    "windows/nanoserver",
    "windows/nanoserver/insider",
    "windows/server/insider",
    "windows/servercore",
    "windows/server",
    "windows/servercore/insider",
    "windows/ml/insider",
    "windows/layerstorage"
] }
```

Also found few .NET images as well:

```json
{ [
    "dotnet/framework/runtime",
    "dotnet/framework/aspnet",
    "dotnet/framework/wcf",
    "dotnet/framework/samples",
    "dotnet/framework/sdk",
    "dotnet/core/aspnet",
    "dotnet/core/runtime",
    "dotnet/core/runtime-deps",
    "dotnet/core/samples",
    "dotnet/core/sdk",
    "dotnet/aspnet"
]}
```

To make the base image selection easier, I follow this flow:

![target-os](target-os.png)

For Windows based deployments, the choice will be between Windows Server Core and Windows Nano Server depending on you apps requirements.