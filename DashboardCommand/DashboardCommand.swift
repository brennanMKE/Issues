import IssuesDashboardCLI

@main
struct DashboardCommand {
    static func main() async { await IssuesDashboardCLIRunner.main() }
}
