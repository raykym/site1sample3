package Site1::Controller::Webroom;
use Mojo::Base 'Mojolicious::Controller';

use utf8;
use Mojo::JSON qw(encode_json decode_json from_json to_json);
#use Mojo::Pg::PubSub;
use Mojo::Util qw(dumper encode decode url_escape url_unescape md5_sum sha1_sum);
use Mojo::Redis2;

use DateTime;

use Data::Dumper;

#my $tablename;
my $clients = {};

sub signaling {
  my $self = shift;

     #Chatroom.pmのsignaringとroomentrylistをマージした処理を作る。
     # connectの同期を取るためにreadyフラグを用意している。
     # さらにチャットも機能させる
     # open対応にスイッチを設定r=open 動作しない。。。

    #cookieからsid取得 認証を経由している前提
    my $sid = $self->cookie('site1');
       $self->app->log->debug("DEBUG: SID: $sid");
    my $uid = $self->stash("uid");
    my $username = $self->stash('username');
    my $icon = $self->stash('icon');
    my $icon_url = $self->stash('icon_url');
       $icon_url = "/imgcomm?oid=$icon" if (! defined $icon_url);

    #websocket 確認
       $self->app->log->debug(sprintf 'Client connected: %s', $self->tx->connection);
       my $id = sprintf "%s", $self->tx;
          $self->app->log->debug("socket id: $id");
      $clients->{$id} = $self->tx;

    # WebSocket接続維持設定
       my $stream = Mojo::IOLoop->stream($self->tx->connection);
        #  $stream->timeout(90);
          $self->inactivity_timeout(500);

    # エントリーメンバー一覧を返す処理 global変数として残す
    my $memberlist;
    my $chatroomname;
    my $entry_json;
    my $altmemberlist = [];

#受信用リスト
my @recvlist;
   @recvlist = ( $sid );

    # on message・・・・・・・
       $self->on(message => sub {
                  my ($self, $msg) = @_;
                   # $msgはJSONキャラを想定
                   my $jsonobj = from_json($msg);
                   $self->app->log->debug("DEBUG: on session: $sid");
                   $self->app->log->debug("DEBUG: msg: $msg");

           if ( $jsonobj->{dummy} ) {
                   # dummy pass
                   return;
              }

           # fromとしてsidを付加
               $jsonobj->{from} = $sid;
               $msg = to_json($jsonobj);
               $self->app->log->debug("DEBUG: msgaddid: $msg");

           # room作成 {entry:room名}受信
           if ( $jsonobj->{entry} ) {

                      # 受信リストの追加
                      push(@recvlist,$jsonobj->{entry});

                   # nameはsubscribe用
                   $chatroomname = "$jsonobj->{entry}";

                      # 0 is false
                   my $entry = { connid => $sid, username => $username, icon_url => $icon_url, ready => 0 };

                      $entry_json = to_json($entry);

                   #重複を避ける為に一度削除、空処理も有り
                   $self->redis->del("LIST$chatroomname$sid");

                   #list用キーの設定
                   $self->redis->set("LIST$chatroomname$sid" => $entry_json);
                   $self->redis->expire( "LIST$chatroomname$sid" => 3600 );

                   $self->app->log->debug("DEBUG: $username entry finish.");             


                   $self->redis->subscribe(\@recvlist, sub {
                           my ($redis, $err) = @_;
                                 #     return $redis->publish('errmsg' => $err) if $err;
                                 return $redis->incr(@recvlist);
                           });
                   $self->redis->expire( $sid => 3600 );
                   $self->redis->expire( $chatroomname => 3600 );

                    return;
                  } # $jsonobj->{entry}

              # setReadyを受信  connidを受信するが、利用しなくなった。Redisの為
              if ($jsonobj->{setReady}) {
                  $self->app->log->debug("setreadyconn: $jsonobj->{setReady}");

                  # LIST更新  1 is true
                   my $entry = { connid => $sid, username => $username, icon_url => $icon_url, ready => 1 };
                      $entry_json = to_json($entry);

                  # 結果はgetlistが呼ばれるのでこれだけ

                   #キーの更新
                   $self->redis->set("LIST$chatroomname$sid" => $entry_json);

                  $self->app->log->debug("DEBUG: setReady on $username");
                 return;

              } # setReady

              #gpslocationを受信  今は使わないと思う
              if ($jsonobj->{gpslocation}) {
                    
                  return;
              } # gpslocation


              # sendtoが含まれる場合
                if ($jsonobj->{sendto}){
                   #個別送信が含まれる場合、単独送信

                   my $jsontxt = to_json($jsonobj);
                   
                   $self->redis->publish( $jsonobj->{sendto} , $jsontxt);
                   $self->redis->expire( $jsonobj->{sendto} => 3600 );
                   $self->app->log->debug("DEBUG: sendto: $jsonobj->{sendto} ");
  
                   return;  # スルーすると全体通信になってしまう。
                   } 



        #エントリーメンバーを送信コマンドの受信 自分宛て
             if ($jsonobj->{getlist}){
 
                  $altmemberlist = [];

                 my $roomkeylist = $self->redis->keys("LIST$chatroomname*");
                 my $roomkeylistdump = to_json($roomkeylist);
                    $self->app->log->debug("DEBUG: roomkeylist: $roomkeylistdump");

                 foreach my $aline (@$roomkeylist) {
                     push (@$altmemberlist, $self->redis->get($aline) );
                     }

                 my $altmemberlistdump = to_json($altmemberlist);
                 $self->app->log->debug("DEBUG: altmemberlist: $altmemberlistdump"); 

        # 配列で１ページ分を送る。
             my $memberlist_json = to_json( { from => $sid, type => "reslist", reslist => $altmemberlist } );   
 
                 $self->app->log->debug("DEBUG: memberlist: $memberlist_json ");

                 $clients->{$id}->send($memberlist_json);

                 return;
                } 

        # roomからエントリー削除
            if ($jsonobj->{bye}){
                   # LISTから削除
                   $self->redis->del("LIST$chatroomname$sid");

                   # リスナー登録の解除 
                   $self->redis->unsubscribe(\@recvlist);
                   $self->app->log->debug("DEBUG: unsbscribe $username ");
                   $self->redis->expire($sid => 3600 );
                   $self->redis->expire($chatroomname => 3600 );
                 return;
               } # {bye}

                 # チャットルーム全体に送信
                       my $jsontxt = to_json($jsonobj);
                       $self->redis->publish( "$chatroomname" , $jsontxt);
                       $self->redis->expire( $chatroomname => 3600 );
                       $self->app->log->debug("DEBUG: publish: $username :  $chatroomname : $jsontxt");

                }); # onmessageのはず。。。

    # on finish・・・・・・・
         $self->on(finish => sub{
               my ($self, $msg) = @_;

            # pubsubのunsubscribe
               $self->redis->unsubscribe(\@recvlist);
               $self->redis->expire( $sid => 1);
               $self->redis->expire( $chatroomname => 1);
               $self->redis->expire( "LIST$chatroomname$sid" => 1);

            # LIST登録の解除 
      #      my $delres = $self->redis->del("LIST$chatroomname$sid");
      #      $self->app->log->debug("DEBUG: delres: $delres");

               $self->app->log->debug('Client disconnected');
               delete $clients->{$id};

        });  # onfinish...

         #redis receve
         $self->redis->on(message => sub {
                my ($redis,$mess,$channel) = @_;

           #     if ( $channel == 'WALKCHAT' ) { return; } # WALKCHATは除外する
                    $self->app->log->debug("DEBUG: on channel: {$channel} ($username) $mess");
                     
                    my $messobj = from_json($mess);

                    #websocket送信 perl形式->jsonへ変換されている。
                    $clients->{$id}->send({json => $messobj});

                    return;
                 });  # redis on message

        $self->redis->subscribe(\@recvlist, sub {
                 my ($redis, $err) = @_;
                       #     return $redis->publish('errmsg' => $err) if $err;
                       return $redis->incr(@recvlist);
                 });
        $self->redis->expire( \@recvlist => 3600 );

#  $self->render(msg => '');
}


my $stream_io = {};
my $redis_pubsub = {};

sub webpubsub {
    my $self = shift;
    # websocket,redisでのpubsub、手続きを簡便に処理する。
    # JSONを受け取って、fromを付けてpubsubで送信する。
    # sendtoが在ると個別送信としてpubsubで送信する
    # entryが来ると共有pubsubとして利用する

    #cookieからsid取得 認証を経由している前提
    my $sid = $self->cookie('site1');
       $self->app->log->debug("DEBUG: SID: $sid");
    my $uid = $self->stash("uid");
    my $username = $self->stash('username');
    my $icon = $self->stash('icon');
    my $icon_url = $self->stash('icon_url');
       $icon_url = "/imgcomm?oid=$icon" if (! defined $icon_url);

       $self->app->plugin('Config');
    my $redisserver = $self->app->config->{redisserver};

    #redisをチャットでは別で設定する。 Site1.pmで共有設定をするとセッション数が上がりすぎてダメになる
    my $redis ||= Mojo::Redis2->new( url => "redis://$redisserver:6379");

    #websocket 確認
       my $wsid = $self->tx->connection;
       $self->app->log->debug(sprintf 'Client connected: %s', $self->tx->connection);
       $clients->{$wsid} = $self->tx;

    my $recvlist = '';
    #   my @recvArray = ( $wsid );
       $redis_pubsub->{$wsid} ||= [ $wsid ];  # @recvArrayの置き換え

    # WebSocket接続維持設定
          $stream_io->{$wsid} = Mojo::IOLoop->stream($self->tx->connection);
          $stream_io->{$wsid}->timeout(70);   # 70sec timeout  ページ遷移してもセッションが残らないように
          $self->inactivity_timeout(60000); #60sec   50secでdummyが送信される

    # on message・・・・・・・
       $self->on(message => sub {
                  my ($self, $msg) = @_;
                   # on messageはブラウザからのみ 他のユーザからはredis経由になる

                   $self->app->log->debug("DEBUG: $username ws message: $msg ");

                   # $msgはJSONキャラを想定
                   my $jsonobj = from_json($msg);

                  # fromとしてwsidを付加
                      $jsonobj->{from} = $wsid;

                  if ( $jsonobj->{dummy} ) {
                       # dummy pass
		       #  $redis->expire( \@recvArray => 300 );
		      $redis->expire( $redis_pubsub->{$wsid} => 300 );
                      $redis->expire( "ENTRY$recvlist$wsid" => 300 );
                       return;
                      }
 
                  # entry pubsubの設定
                  if ( $jsonobj->{entry} ) {

                      $recvlist = $jsonobj->{entry};
		      #  push (@recvArray, $recvlist);
                      push (@{$redis_pubsub->{$wsid}}, $recvlist);
		      #$redis->subscribe(\@recvArray, sub {
		      $redis->subscribe( $redis_pubsub->{$wsid}, sub {
                                 my ($redis, $err) = @_;
				     #return $redis->incr(@recvArray);
                                     return $redis->incr(@$redis_pubsub->{$wsid});
                            });

		    #$redis->expire( \@recvArray => 300 );
                      $redis->expire( $redis_pubsub->{$wsid} => 300 );

                      my $entry = { connid => $wsid, username => $username, icon_url => $icon_url };

                      my $entry_json = to_json($entry);

                      #list用キーの設定
                      $redis->set("ENTRY$recvlist$wsid" => $entry_json);
                      $redis->expire( "ENTRY$recvlist$wsid" => 300 );

                      $self->app->log->debug("DEBUG: $username entry finish.");

                     return; 
                     }

                   #エントリーメンバーを送信コマンドの受信 自分宛て
                   if ($jsonobj->{getlist}){
 
                      my $altmemberlist = [];

                      my $roomkeylist = $redis->keys("ENTRY$recvlist*");
                      my $roomkeylistdump = to_json($roomkeylist);
                         $self->app->log->debug("DEBUG: roomkeylist: $roomkeylistdump");

                      foreach my $aline (@$roomkeylist) {
                             push (@$altmemberlist, $redis->get($aline) );
                         }

                      my $altmemberlistdump = to_json($altmemberlist);
                         $self->app->log->debug("DEBUG: altmemberlist: $altmemberlistdump"); 

                      # 配列で１ページ分を送る。
                      my $memberlist_json = to_json( { from => $wsid, type => "reslist", reslist => $altmemberlist } );   
 
                         $self->app->log->debug("DEBUG: memberlist: $memberlist_json ");

                         $clients->{$wsid}->send($memberlist_json);

                         return;
                        } 

                  # sendtoが含まれる場合
                  if ($jsonobj->{sendto}){
                     #個別送信が含まれる場合、単独送信

                     my $jsontxt = to_json($jsonobj);
                     
                     $redis->publish( $jsonobj->{sendto} , $jsontxt);
                  #   $redis->expire( $jsonobj->{sendto} => 300 );
                     $self->app->log->debug("DEBUG: sendto: $jsonobj->{sendto} ");
  
                     return;  # スルーすると全体通信になってしまう。
                     } 

                  if ($jsonobj->{bye}){
                         # ClientからClose

                         $clients->{$wsid}->finish;
                  }


                  # グループ内通信
                     my $jsontext = to_json($jsonobj);
                     $redis->publish( $recvlist , $jsontext); #websocketで受信したら、redisに送信する
                  #   $redis->expire( $recvlist => 300 );
                     $self->app->log->debug("DEBUG: publish: $username :  $recvlist : $jsontext");

                }); # onmessageのはず。。。

    # on finish・・・・・・・
         $self->on(finish => sub{
               my ($self, $msg) = @_;

                   # redisのエントリーを削除
		   #$redis->unsubscribe(\@recvArray);
                   $redis->unsubscribe($redis_pubsub->{$wsid});
                   $redis->del("ENTRY$recvlist$wsid");
                   $redis->del("$wsid");

                   delete $stream_io->{$wsid};
                   delete $clients->{$wsid};
		   delete $redis_pubsub->{$wsid};

         return;
        });  # onfinish...

    #redis receve
         $redis->on(message => sub {
                my ($redis,$mess,$channel) = @_;

                   if (( $channel eq $recvlist ) || ( $channel eq $wsid )) {
                        $self->app->log->debug("DEBUG: $username redis on message: $channel | $mess ");
                        $clients->{$wsid}->send($mess); # redisは受信したらwebsocketで送信
                      }

          });  # redis on message

        # redis受信用
	#$redis->subscribe(\@recvArray, sub {
        $redis->subscribe( $redis_pubsub->{$wsid}, sub {
                 my ($redis, $err) = @_;
		       #return $redis->incr(@recvArray);
                       return $redis->incr(@$redis_pubsub->{$wsid});
                 });
	 #$redis->expire( \@recvArray => 300 );
        $redis->expire( $redis_pubsub->{$wsid} => 300 );

        #個別送信用
  #      $redis->subscribe($wsid, sub {
  #               my ($redis, $err) = @_;
  #                     return $redis->incr($wsid);
  #               });
  #      $redis->expire( $wsid => 300 );

#    $self->render(); 
}

sub testpubsub {
    my $self = shift;

    $self->render();
}

sub webpubsubmemo {
    my $self = shift;
    # webpubsubからコピーして、memoshare用の処理を追加したもの

    #cookieからsid取得 認証を経由している前提
    my $sid = $self->cookie('site1');
       $self->app->log->debug("DEBUG: SID: $sid");
    my $uid = $self->stash("uid");
    my $username = $self->stash('username');
    my $icon = $self->stash('icon');
    my $icon_url = $self->stash('icon_url');
       $icon_url = "/imgcomm?oid=$icon" if (! defined $icon_url);

    my $once = 1;

       $self->app->plugin('Config');
    my $redisserver = $self->app->config->{redisserver};

    #redisをチャットでは別で設定する。 Site1.pmで共有設定をするとセッション数が上がりすぎてダメになる
    my $redis ||= Mojo::Redis2->new( url => "redis://$redisserver:6379");

    my $redis_memo = $self->app->redis;

    #websocket 確認
       my $wsid = $self->tx->connection;
       $self->app->log->debug(sprintf 'Client connected: %s', $self->tx->connection);
       $clients->{$wsid} = $self->tx;

    my $recvlist = '';
    #   my @recvArray = ( $wsid );
       $redis_pubsub->{$wsid} ||= [ $wsid ];  # @recvArrayの置き換え

    # mongodb setup   
    my $msdb = $self->app->mongoclient->get_database('MemoShare');
    my $mscoll;

    # WebSocket接続維持設定
          $stream_io->{$wsid} = Mojo::IOLoop->stream($self->tx->connection);
          $stream_io->{$wsid}->timeout(70);   # 70sec timeout  ページ遷移してもセッションが残らないように
          $self->inactivity_timeout(60000); #60sec   50secでdummyが送信される




    # on message・・・・・・・
       $self->on(message => sub {
                  my ($self, $msg) = @_;
                   # on messageはブラウザからのみ 他のユーザからはredis経由になる

                   $self->app->log->debug("DEBUG: $username ws message: $msg ");

                   # $msgはJSONキャラを想定
                   my $jsonobj = from_json($msg);

                  # fromとしてwsidを付加
                      $jsonobj->{from} = $wsid;

                  if ( $jsonobj->{dummy} ) {
                       # dummy pass
		       #  $redis->expire( \@recvArray => 300 );
		      $redis->expire( $redis_pubsub->{$wsid} => 300 );
                      $redis->expire( "ENTRY$recvlist$wsid" => 300 );
                       return;
                      }
 
                  # entry pubsubの設定
                  if ( $jsonobj->{entry} ) {

                      $recvlist = $jsonobj->{entry};
		      #  push (@recvArray, $recvlist);
                      push (@{$redis_pubsub->{$wsid}}, $recvlist);
		      #$redis->subscribe(\@recvArray, sub {
		      $redis->subscribe( $redis_pubsub->{$wsid}, sub {
                                 my ($redis, $err) = @_;
				     #return $redis->incr(@recvArray);
                                     return $redis->incr(@$redis_pubsub->{$wsid});
                            });

		    #$redis->expire( \@recvArray => 300 );
                      $redis->expire( $redis_pubsub->{$wsid} => 300 );

                      my $entry = { connid => $wsid, username => $username, icon_url => $icon_url };

                      my $entry_json = to_json($entry);

                      #list用キーの設定
                      $redis->set("ENTRY$recvlist$wsid" => $entry_json);
                      $redis->expire( "ENTRY$recvlist$wsid" => 300 );

		      $mscoll = $msdb->get_collection("$recvlist");
                      if ( defined $mscoll ){
                          $self->app->log->info("DEBUG: set mscoll $recvlist");
                      }

                      $self->app->log->info("DEBUG: $username entry finish.");

                        # 初回だけmemoをチェックする
                        if ( $once == 1 ) {	  
			      my $jsonmemo = "";
			         $jsonmemo = $redis_memo->get("MEMO$recvlist");

                              my $memojson = to_json({'resmemo' => $jsonmemo});
			      $self->app->log->info("DEBUG: resmemo: $memojson");
		              $clients->{$wsid}->send($memojson) if ( $jsonmemo ne "");  # 自分に送る

                              $once = 0;
                        }

                     return; 
                     }

                   #エントリーメンバーを送信コマンドの受信 自分宛て
                   if ($jsonobj->{getlist}){
 
                      my $altmemberlist = [];

                      my $roomkeylist = $redis->keys("ENTRY$recvlist*");
                      my $roomkeylistdump = to_json($roomkeylist);
                         $self->app->log->debug("DEBUG: roomkeylist: $roomkeylistdump");

                      foreach my $aline (@$roomkeylist) {
                             push (@$altmemberlist, $redis->get($aline) );
                         }

                      my $altmemberlistdump = to_json($altmemberlist);
                         $self->app->log->debug("DEBUG: altmemberlist: $altmemberlistdump"); 

                      # 配列で１ページ分を送る。
                      my $memberlist_json = to_json( { from => $wsid, type => "reslist", reslist => $altmemberlist } );   
 
                         $self->app->log->debug("DEBUG: memberlist: $memberlist_json ");

                         $clients->{$wsid}->send($memberlist_json);

                         return;
                        } 

                  # sendtoが含まれる場合
                  if ($jsonobj->{sendto}){
                     #個別送信が含まれる場合、単独送信

                     my $jsontxt = to_json($jsonobj);
                     
                     $redis->publish( $jsonobj->{sendto} , $jsontxt);
                  #   $redis->expire( $jsonobj->{sendto} => 300 );
                     $self->app->log->debug("DEBUG: sendto: $jsonobj->{sendto} ");
  
                     return;  # スルーすると全体通信になってしまう。
                     } 

                  if ($jsonobj->{bye}){
                         # ClientからClose

                         $clients->{$wsid}->finish;
			 return;
                  }


		  if ( $jsonobj->{text} ){
			  $self->app->log->info("DEBUG: recv: $jsonobj->{text} ");
			  # 書き込んだ人が共有領域に書き込む
			  
                          my $memoname = "MEMO$recvlist";

		          $redis_memo->set("$memoname" => "$jsonobj->{text}");  
			  $redis_memo->expire("$memoname" => 3600 ); # とりあえず１時間
			  my $relmem = { 'reloadtext' => 'dummy' };
                          my $relmemjson = to_json($relmem);
                             $redis->publish( $recvlist , $relmemjson); # 他のメンバーに送信する
		      return;
	          }

		  if ( $jsonobj->{getmemo} ) {
                      # 途中参加の場合、現状のメモを送信する

			  my $jsonmemo = $redis_memo->get("MEMO$recvlist");

		      	  my $memojson = to_json({'resmemo' => $jsonmemo});
			  $self->app->log->info("DEBUG: resmemo: $memojson");
		          $clients->{$wsid}->send($memojson);  # 自分に送る
		      return;
                  }

		  if ( $jsonobj->{editmemo} ) {
                      # editmemoがpubsubされる  各ユーザー画面リロード
		      delete $jsonobj->{from};
                      my $editmemo = to_json($jsonobj);
                      $redis->publish( $recvlist, $editmemo );

                      return;
		  }

		  if ( $jsonobj->{writememo} ) {
                      my $dt = DateTime->now( time_zone => $jsonobj->{timezone} );
                      my $memoname = "$recvlist$dt";
                      my $data = { "name" => $memoname , "memo" => $jsonobj->{writememo} };
		      my $datajson = to_json($data);

		         $mscoll->insert_one($data);

			 $self->app->log->info("DEBUG: writememo done. $datajson");

			 undef $memoname;
			 undef $data;
			 undef $dt;

                      return;
		  }

                  # グループ内通信
                     my $jsontext = to_json($jsonobj);
                     $redis->publish( $recvlist , $jsontext); #websocketで受信したら、redisに送信する
                  #   $redis->expire( $recvlist => 300 );
                     $self->app->log->debug("DEBUG: publish: $username :  $recvlist : $jsontext");

                }); # onmessageのはず。。。

    # on finish・・・・・・・
         $self->on(finish => sub{
               my ($self, $msg) = @_;

                   # redisのエントリーを削除
		   #$redis->unsubscribe(\@recvArray);
                   $redis->unsubscribe($redis_pubsub->{$wsid});
                   $redis->del("ENTRY$recvlist$wsid");
                   $redis->del("$wsid");

                   delete $stream_io->{$wsid};
                   delete $clients->{$wsid};
		   delete $redis_pubsub->{$wsid};

		   undef $mscoll;  # コレクションを解除

		   $once = 1;  # 初期化

         return;
        });  # onfinish...

    #redis receve
         $redis->on(message => sub {
                my ($redis,$mess,$channel) = @_;

                   if (( $channel eq $recvlist ) || ( $channel eq $wsid )) {
                        $self->app->log->debug("DEBUG: $username redis on message: $channel | $mess ");
                        $clients->{$wsid}->send($mess); # redisは受信したらwebsocketで送信
                      }

          });  # redis on message

        # redis受信用
	#$redis->subscribe(\@recvArray, sub {
        $redis->subscribe( $redis_pubsub->{$wsid}, sub {
                 my ($redis, $err) = @_;
		       #return $redis->incr(@recvArray);
                       return $redis->incr(@$redis_pubsub->{$wsid});
                 });
	 #$redis->expire( \@recvArray => 300 );
        $redis->expire( $redis_pubsub->{$wsid} => 300 );


}

1;
