using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace AutomateIt.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddUserTokensAndEmail : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "UserEmail",
                table: "Automations",
                type: "text",
                nullable: true);

            migrationBuilder.CreateTable(
                name: "UserTokens",
                columns: table => new
                {
                    Email = table.Column<string>(type: "text", nullable: false),
                    AccessToken = table.Column<string>(type: "text", nullable: false),
                    RefreshToken = table.Column<string>(type: "text", nullable: false),
                    ExpiryUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_UserTokens", x => x.Email);
                });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "UserTokens");

            migrationBuilder.DropColumn(
                name: "UserEmail",
                table: "Automations");
        }
    }
}
