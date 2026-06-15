# Build stage
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Copy all csproj files and restore
COPY ["AutomateIt.API/AutomateIt.API.csproj", "AutomateIt.API/"]
COPY ["AutomateIt.Core/AutomateIt.Core.csproj", "AutomateIt.Core/"]
COPY ["AutomateIt.Infrastructure/AutomateIt.Infrastructure.csproj", "AutomateIt.Infrastructure/"]
RUN dotnet restore "AutomateIt.API/AutomateIt.API.csproj"

# Copy everything else and build
COPY . .
WORKDIR "/src/AutomateIt.API"
RUN dotnet build "AutomateIt.API.csproj" -c Release -o /app/build

# Publish stage
FROM build AS publish
RUN dotnet publish "AutomateIt.API.csproj" -c Release -o /app/publish /p:UseAppHost=false

# Final runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS final
WORKDIR /app
COPY --from=publish /app/publish .

# Set environment to Production
ENV ASPNETCORE_ENVIRONMENT=Production
# Railway uses the PORT environment variable
ENV ASPNETCORE_URLS=http://+:5161

ENTRYPOINT ["dotnet", "AutomateIt.API.dll"]
