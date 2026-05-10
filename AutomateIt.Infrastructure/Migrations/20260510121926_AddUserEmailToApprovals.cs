using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace AutomateIt.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddUserEmailToApprovals : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "UserEmail",
                table: "EmailApprovals",
                type: "text",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "UserEmail",
                table: "EmailApprovals");
        }
    }
}
