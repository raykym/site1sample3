use Mojo::Base -strict;

use Test::More;
use Test::Mojo;
use feature 'say';

my $t = Test::Mojo->new('Site1');
   $t->ua->max_redirects(2);

my $email = 'test1@test.com';
my $emailpass = 'test1_pass';
my $server = 'westwind.backbone.site';

subtest 'Top page' => sub {
    $t->get_ok('/')->status_is(200)->content_like(qr/Mojolicious/i);
};

# 入力ミスでログインページに飛ぶ
subtest 'Login miss' => sub {
   my $email = 'testtest@test.com';

   $t->post_ok('/signinact' => form => { email => $email, password => $emailpass})
     ->status_is(200)
     ->content_like(qr/e-mail or password Not match!/);

  #  my $content = $t->tx->res->body;
  #  say $content;

};


subtest 'Login' => sub {
  # 認証にcoolieが必要なのでproxy経由のパスを指定しないと動作しない

  #  my $tx = $t->ua->build_tx(POST => '/signinact' => form => { email => $email, password => $emailpass });
    ###  $tx->req->cookies({name => 'user', value => 'sri'});
  #     $t->request_ok($tx)->status_is(200);

    $t->post_ok("https://$server/signinact" => form => { email => $email, password => $emailpass })
      ->status_is(200)
      ->content_like(qr/OPEN the Menu!/);

  #  my $content = $t->tx->res->body;
  #  say $content;

  #  my $cookies = $t->ua->cookie_jar->all;
  #  for my $i (@$cookies){
  #      say $i;
  #  }

};


subtest 'websocket' => sub {
# WebSocket
# TEST用応答を組み込んだ(dummy)

    $t->websocket_ok("https://$server/walkworld")
      ->send_ok('{"dummy":"testdata"}')
      ->message_ok
      ->message_is('{"dummy":"testdata"}')
      ->finish_ok;
};

done_testing();
