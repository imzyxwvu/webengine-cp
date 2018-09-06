var PageMgr = { pageList: [], pages: {} };

PageMgr.showPage = function(pageId) {
	var page = this.pages[pageId];
	this.current = page;
	this.loadUrl(page.url);
}

PageMgr.loadToCurrent = function(html) {
	var page = this.current;
	page.el.innerHTML = html;
	$(page.el).show(300);
	$(page.el).find('a').each(function() {
		if(this.target == "_blank") return;
		this.onclick = function() {
			PageMgr.loadUrl(this.href);
			return false;
		}
	});
	$(page.el).find('form').each(function() {
		this.onsubmit = function(e) {
			PageMgr.postForm(this);
			return false;
		}
	});
}

PageMgr.postForm = function(form) {
	var data = {};
	$(form).find('input[type=text]').each(function() {
		if(this.dataset.name)
			data[this.dataset.name] = this.value;
	});
	$.post(form.action, data, function(resp) {
		PageMgr.loadToCurrent(resp);
	});
}

PageMgr.loadUrl = function(url) {
	$('.page').hide();
	$.get(url, function(resp) {
		PageMgr.loadToCurrent(resp);
	});
}

PageMgr.createPage = function(pageId, url) {
	var page = document.createElement('div');
	page.className = 'page page-' + pageId;
	page.dataset.page = pageId;
	PageMgr.pageList.push(pageId);
	PageMgr.pages[pageId] = { el: page, url: url};
	$('.main').append(page);
}

$('.sidebar-nav-item').each(function() {
	var pageId = this.dataset.page;
	PageMgr.createPage(pageId, this.dataset.url);
	this.onclick = function() {
		PageMgr.showPage(this.dataset.page);
	};
});

PageMgr.showPage(PageMgr.pageList[0])