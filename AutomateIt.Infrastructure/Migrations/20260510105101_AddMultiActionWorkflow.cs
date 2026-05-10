using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace AutomateIt.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddMultiActionWorkflow : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "ActionConfig",
                table: "Automations");

            migrationBuilder.DropColumn(
                name: "ActionType",
                table: "Automations");

            migrationBuilder.CreateTable(
                name: "AutomationActions",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    AutomationId = table.Column<Guid>(type: "uuid", nullable: false),
                    ActionType = table.Column<string>(type: "text", nullable: false),
                    ActionConfig = table.Column<string>(type: "jsonb", nullable: false),
                    Order = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_AutomationActions", x => x.Id);
                    table.ForeignKey(
                        name: "FK_AutomationActions_Automations_AutomationId",
                        column: x => x.AutomationId,
                        principalTable: "Automations",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_AutomationActions_AutomationId",
                table: "AutomationActions",
                column: "AutomationId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "AutomationActions");

            migrationBuilder.AddColumn<string>(
                name: "ActionConfig",
                table: "Automations",
                type: "jsonb",
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<string>(
                name: "ActionType",
                table: "Automations",
                type: "text",
                nullable: false,
                defaultValue: "");
        }
    }
}
