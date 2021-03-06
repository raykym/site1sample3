//server workerにインストールされるスクリプト
//プッシュ通知が行われると「push」イベントが起動する
self.addEventListener("install", function(event) {
    self.skipWaiting();
    console.log("Installed", event);
});

self.addEventListener("activate", function(event) {
    console.log("Activated", event);
});

self.addEventListener("push", function(event) {
    console.log("Push message received", event);
    event.waitUntil(getEndpoint().then(function(endpoint) {
        var form = new FormData();
            form.set('endpoint', endpoint);
        //通知内容をサーバに取得しに行きます。
        return fetch("https://westwind.backbone.site/notifications"
             ,
           {
              credentials: "include",
              method: 'POST',
                body: form
           }
            ).then(function(response) {
                if (response.status === 200) {
                    return response.json();
                }
                throw new Error("notification api response error")
                    }).then(function(response) {
                        //TODO デザインやボタンの有無などの調整が必要
                        return self.registration.showNotification(response.title, {
                            icon: response.icon,
                            body: response.body,
                            tag: "push-test",
                //            actions: [{
                //                action: "act1",
                //                title: "ボタン１"
                //            }, {
                //                action: "act2",
                //                title: "ボタン２"
                //            }],
                //            vibrate: [200, 100, 200, 100, 200, 100, 200],
                            data: {
                                url: response.url
                            }
                        });
                     });
 }));
});
//押したaction名はnotificationclickのevent.actionで取得できます。

self.addEventListener("notificationclick", function(event) {
    console.log("notification clicked:" + event);
    console.log("action:" + event.action);
    event.notification.close();

    var url = "https://westwind.backbone.site/menu";
    if (event.notification.data.url) {
        url = event.notification.data.url
    }

    event.waitUntil(
            clients.matchAll({type: "window"}).then(function() {
            if(clients.openWindow) {
              return clients.openWindow(url)
            }
        })
    );
});

function getEndpoint() {
    return self.registration.pushManager.getSubscription().then(function(subscription) {
        if (subscription) {
            return subscription.endpoint;
        }
        throw new Error("User not subscribed");
    });
}
