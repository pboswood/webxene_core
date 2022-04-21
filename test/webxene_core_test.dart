import 'package:test/test.dart';
import 'package:webxene_core/auth_manager.dart';
import 'package:webxene_core/instance_manager.dart';
import 'package:webxene_core/motes/mote.dart';

void main() {
	/*
		// Get the specific group we are testing. Normally bound to some kind of selector, etc.
		final groupClicked = myGroups.firstWhere((group) => group.name == "Invoice Group");

		// Fetch a single group + the menu of pages inside it.
		final sampleGroup = await GroupManager().fetchGroup(groupClicked.id);
		ret += "Loaded sample group: ${sampleGroup.id} / ${sampleGroup.name}\n";
		final samplePage = sampleGroup.orderedMenu.firstWhere((page) => page.name == "Invoices");
		ret += "Loaded sample menu-page: ${samplePage.id} / ${samplePage.name} (menu position ${samplePage.menuOrder})\n";

		// Fetch a single page + all data motes inside it.
		final fullSamplePage = await GroupManager().fetchPageAndMotes(samplePage.id, forceRefresh: true);
		ret += "Loaded sample full-page: ${fullSamplePage.id} / ${fullSamplePage.name}\n";
		ret += "Found ${fullSamplePage.cachedMotes.length} motes in sample full-page.\n";

		// Get carddeck columns from this page for rendering.
		ret += "Found ${fullSamplePage.columns.length} columns in sample page:\n";
		ret += fullSamplePage.columns.values.map((c) => c.title).join(", ") + "\n";

		// Fetch all filters possible for a single column.
		MoteColumn sampleColumn = fullSamplePage.columns.values.firstWhere((c) => c.title == "Customers");
		ret += "Selected column: #${sampleColumn.id} ${sampleColumn.title}\n";
		final filterList  = sampleColumn.allPossibleFilters();
		ret += "Possible filters: " + filterList.join(',') + "\n";

		// Add a filter and display matching motes.
		sampleColumn.filters.add(Filter.andFilter("cf_customer_code", 123));
		ret += "Added filter for cf_customer_code = 123\n";
		var moteView = sampleColumn.getMoteView();
		ret += "Got mote view of ${moteView.length} motes from column:\n";
		var interpretation = Mote.interpretMotesCSV(moteView);
		var header = interpretation.item1, data = interpretation.item2;
		ret += header + "\n";
		for (var datum in data) {
			ret += datum + "\n";
		}

		// Remove filter and display all motes.
		sampleColumn.filters.clear();
		moteView = sampleColumn.getMoteView();
		interpretation = Mote.interpretMotesCSV(moteView);
		data = interpretation.item2;
		ret += "Unfiltered data: found ${data.length} motes.\n";

		// Run a benchmark for loading ~100 motes. These are motes with ID from 4508-4600 in group 7.
		final timerLoad = Stopwatch()..start();
		List<int> benchmarkIds = [for (var i = 4508; i <= 4600; i++) i ];
		final sampleMotes = await MoteManager().fetchMotes(benchmarkIds, 7);
		final sampleMotesCSV = Mote.interpretMotesCSV(sampleMotes);
		timerLoad.stop();
		ret += "\n\nBenchmark: Fetched+interpreted ${sampleMotesCSV.item2.length} motes in ${timerLoad.elapsedMilliseconds}ms.";

		return ret;
	*/

	test('Initialize instance', () {
		InstanceManager().setupInstance("netxene.cirii.org", { 'instance': {'DEBUG_HTTP': true }});

	});

	test('Login as user', () async {
		const String testUser = "alice@example.com";
		const String testPass = "alice";
		expect(AuthManager().state, AuthState.init);
		await AuthManager().runSingleStageLogin(testUser, testPass);
		expect(AuthManager().state, AuthState.complete);
	});

	test('Fetch user groups list', () async {
		final g = await AuthManager().loggedInUser.getSelfGroupsList();
		expect(g.length, greaterThan(0));
	});


}
